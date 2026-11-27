// PEMILIK: Anggota D. Menggabungkan paket, pemakaian, kategori, planner, dan alert.

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/alert_service.dart';
import '../../services/dashboard_data_limit_calculator.dart';
import '../../services/data_limit_service.dart';
import '../../services/app_usage_sync_service.dart';
import '../../services/planner_service.dart';
import '../../services/usage_service.dart';
import '../../services/usage_totals.dart';

enum DashboardLoad { loading, ready, noPackage, error }

/// Fungsi planner dapat diganti saat pengujian.
typedef DashboardPlanner = PlannerResult Function({
  required DataPackage package,
  required int totalUsedBytes,
  required int todayUsedBytes,
  required DateTime today,
});

/// Pemakaian satu kategori kuota.
class CategoryUsage {
  const CategoryUsage({required this.category, required this.usedBytes});

  final QuotaCategory category;
  final int usedBytes;

  int get capacityBytes => category.capacityBytes;

  int get remainingBytes {
    final remaining = capacityBytes - usedBytes;
    return remaining < 0 ? 0 : remaining;
  }
}

class DashboardProvider extends ChangeNotifier {
  DashboardProvider(
    this._packageRepo,
    UsageRepository usageRepo,
    UsageService usageService,
    this._alertService, {
    this.categoryRepo,
    this.dataLimitRepo,
    this.dataLimitService,
    required AppUsageSyncService syncService,
    DashboardPlanner? planner,
  }) : _usageRepo = usageRepo,
       _usageService = usageService,
       _sync = syncService,
       _planner = planner ?? PlannerService.calculate;

  final PackageRepository _packageRepo;
  final UsageRepository _usageRepo;
  final UsageService _usageService;
  final AlertService _alertService;

  final QuotaCategoryRepository? categoryRepo;
  final DataLimitRepository? dataLimitRepo;

  /// Layanan Data Limit Warning (penyimpanan + notifikasi). Opsional agar
  /// Dashboard tetap dapat dipakai tanpa fitur minggu 2.
  final DataLimitService? dataLimitService;

  final AppUsageSyncService _sync;
  final DashboardPlanner _planner;

  DashboardLoad loadState = DashboardLoad.loading;

  DataPackage? package;
  PlannerResult? plan;
  List<UsageRecord> records = const [];

  List<CategoryUsage> categoryUsage = const [];

  /// Byte APP_USAGE efektif yang tidak memiliki kategori valid.
  int unclassifiedAppBytes = 0;

  /// Selisih DEVICE_TOTAL terhadap jumlah APP_USAGE pada hari yang memakai
  /// DEVICE_TOTAL. Selisih ini tidak pernah dibebankan ke kategori.
  int unmappedDeviceBytes = 0;

  /// Total byte yang tidak masuk kategori mana pun untuk UI lama. Nilainya
  /// gabungan dua state di atas dan tidak memengaruhi perhitungan kategori.
  int get unclassifiedBytes => unclassifiedAppBytes + unmappedDeviceBytes;

  DashboardDataLimitStatus dataLimit = DashboardDataLimitStatus.none;

  Map<DateTime, int> dailyUsage = const {};
  String? errorMessage;

  int totalUsedBytes = 0;

  bool hasPermission = false;
  UsageReading? lastReading;
  AppUsageSyncResult? lastSync;
  String? syncMessage;
  DateTime? lastUpdatedAt;

  bool planUnavailable = false;

  int _generation = 0;
  bool _notifPermissionAsked = false;
  bool _disposed = false;

  /// Memilih satu sumber pemakaian efektif untuk setiap tanggal.
  ///
  /// Prioritas:
  /// 1. MANUAL_TOTAL.
  /// 2. DEVICE_TOTAL.
  /// 3. APP_USAGE.
  ///
  /// DEVICE_TOTAL dan APP_USAGE tidak dijumlahkan bersamaan.
  Map<DateTime, List<UsageRecord>> _buildEffectiveRecords(
    List<UsageRecord> sourceRecords,
  ) {
    return effectiveUsageRecordsByDay(sourceRecords);
  }

  void _resetForNoPackage() {
    package = null;
    plan = null;
    records = const [];

    categoryUsage = const [];
    unclassifiedAppBytes = 0;
    unmappedDeviceBytes = 0;
    dataLimit = DashboardDataLimitStatus.none;

    dailyUsage = const {};
    totalUsedBytes = 0;

    planUnavailable = false;
    errorMessage = null;

    lastReading = null;
    lastSync = null;
    syncMessage = null;
    lastUpdatedAt = null;
  }

  Future<void> refresh(String userId) async {
    final gen = ++_generation;

    if (package == null) {
      loadState = DashboardLoad.loading;
      _notify();
    }

    try {
      final active = await _packageRepo.getActive(userId);

      if (gen != _generation) return;

      if (active == null || active.id == null) {
        _resetForNoPackage();

        hasPermission = await _usageService.hasPermission();

        if (gen != _generation) return;

        loadState = DashboardLoad.noPackage;
        _notify();
        return;
      }

      final packageId = active.id!;

      if (!_notifPermissionAsked) {
        _notifPermissionAsked = true;

        try {
          await _alertService.requestPermission();
        } catch (_) {
          // Kegagalan izin notifikasi tidak boleh menggagalkan Dashboard.
        }
      }

      hasPermission = await _usageService.hasPermission();

      if (gen != _generation) return;

      if (hasPermission) {
        // Sinkronisasi statistik Android ke SQLite.
        // Dashboard membaca data dari repository setelah sinkronisasi.
        final sync = await _sync.syncToday(active);

        if (gen != _generation) return;

        final deviceReading = sync.deviceReading;
        final deviceSaved =
            deviceReading != null && deviceReading.status == UsageReadStatus.ok;
        final appSaved = sync.savedAppRecords > 0;

        lastSync = sync;
        lastReading = deviceReading;
        syncMessage = deviceSaved || appSaved ? null : deviceReading?.message;

        if (deviceSaved || appSaved) {
          lastUpdatedAt = DateTime.now();
        }
      } else {
        lastReading = null;
        lastSync = null;
        syncMessage = null;
      }

      final today = dateOnly(DateTime.now());

      final loadedRecords = await _usageRepo.getRecords(packageId);

      if (gen != _generation) return;

      final allocations = await _usageRepo.getAllocationsByPackage(packageId);

      if (gen != _generation) return;

      final categorySource = categoryRepo;
      final loadedCategories = categorySource == null
          ? const <QuotaCategory>[]
          : await categorySource.getByPackage(packageId);

      if (gen != _generation) return;

      final limitSetting = await dataLimitRepo?.getByPackage(packageId);

      if (gen != _generation) return;

      // Pilih sumber pemakaian efektif untuk setiap tanggal.
      final effectiveRecords = _buildEffectiveRecords(loadedRecords);

      // Hitung pemakaian harian dari catatan efektif.
      final loadedDaily = <DateTime, int>{
        for (final entry in effectiveRecords.entries)
          entry.key: entry.value.fold<int>(
            0,
            (sum, record) => sum + record.totalBytes,
          ),
      };

      final totalUsed = loadedDaily.values.fold<int>(
        0,
        (sum, bytes) => sum + bytes,
      );

      final todayUsed = loadedDaily[today] ?? 0;

      // Sumber alokasi kategori hanya catatan yang memang boleh memiliki
      // alokasi pada hari efektifnya:
      // - hari MANUAL_TOTAL -> alokasi manual pengguna;
      // - hari DEVICE_TOTAL -> APP_USAGE hari itu (DEVICE_TOTAL tidak pernah
      //   dialokasikan);
      // - hari APP_USAGE    -> APP_USAGE itu sendiri.
      // Karena satu hari hanya memakai satu sumber efektif, alokasi dari
      // MANUAL_TOTAL dan APP_USAGE tidak pernah dijumlahkan bersamaan.
      final loadedByDay = <DateTime, List<UsageRecord>>{};

      for (final record in loadedRecords) {
        if (record.networkType == NetworkType.wifi) continue;

        loadedByDay
            .putIfAbsent(dateOnly(record.periodStartAt), () => [])
            .add(record);
      }

      final allocationSourceRecords = <UsageRecord>[];

      for (final entry in effectiveRecords.entries) {
        final manualIsEffective = entry.value.any(
          (record) => record.recordScope == UsageRecordScope.manualTotal,
        );

        if (manualIsEffective) {
          // MANUAL_TOTAL adalah deklarasi total pengguna untuk hari itu;
          // APP_USAGE pada hari yang sama tidak boleh ikut dialokasikan.
          allocationSourceRecords.addAll(
            entry.value.where(
              (record) =>
                  record.id != null &&
                  record.recordScope == UsageRecordScope.manualTotal,
            ),
          );
          continue;
        }

        // DEVICE_TOTAL maupun APP_USAGE sebagai sumber efektif tetap memakai
        // APP_USAGE hari itu untuk kategori. DEVICE_TOTAL tidak dialokasikan.
        allocationSourceRecords.addAll(
          (loadedByDay[entry.key] ?? const <UsageRecord>[]).where(
            (record) =>
                record.id != null &&
                record.recordScope == UsageRecordScope.appUsage,
          ),
        );
      }

      final allocationSourceIds = <String>{
        for (final record in allocationSourceRecords) record.id!,
      };

      // Hitung alokasi hanya dari catatan sumber kategori di atas. Dengan
      // begitu alokasi APP_USAGE tetap terbaca walau DEVICE_TOTAL tersedia.
      final allocatedByCategory = <String, int>{};
      final allocatedByRecord = <String, int>{};

      for (final allocation in allocations) {
        if (!allocationSourceIds.contains(allocation.usageRecordId)) {
          continue;
        }

        final categoryId = allocation.quotaCategoryId;

        if (categoryId != null) {
          allocatedByRecord.update(
            allocation.usageRecordId,
            (value) => value + allocation.allocatedBytes,
            ifAbsent: () => allocation.allocatedBytes,
          );

          allocatedByCategory.update(
            categoryId,
            (value) => value + allocation.allocatedBytes,
            ifAbsent: () => allocation.allocatedBytes,
          );
        }

        // Alokasi UNCLASSIFIED (quota_category_id null) sengaja tidak
        // dihitung sebagai pemakaian kategori.
      }

      // Bentuk ringkasan kategori untuk Dashboard.
      final loadedCategoryUsage = [
        for (final category in loadedCategories)
          CategoryUsage(
            category: category,
            usedBytes: category.id == null
                ? 0
                : allocatedByCategory[category.id!] ?? 0,
          ),
      ];

      // Byte APP_USAGE efektif yang tidak masuk kategori mana pun, termasuk
      // alokasi UNCLASSIFIED. Angka ini berbeda dari selisih perangkat.
      var unclassifiedApp = 0;

      for (final record in allocationSourceRecords) {
        if (record.recordScope != UsageRecordScope.appUsage) continue;

        final allocated = allocatedByRecord[record.id!] ?? 0;
        final remainder = record.totalBytes - allocated;

        if (remainder > 0) {
          unclassifiedApp += remainder;
        }
      }

      // Selisih DEVICE_TOTAL terhadap jumlah APP_USAGE pada hari yang sama.
      // Selisih ini tidak dialokasikan ke kategori dan tidak digabung dengan
      // UNCLASSIFIED milik APP_USAGE.
      final appBytesByDay = <DateTime, int>{};

      for (final record in loadedRecords) {
        if (record.networkType == NetworkType.wifi ||
            record.recordScope != UsageRecordScope.appUsage) {
          continue;
        }

        final day = dateOnly(record.periodStartAt);
        appBytesByDay.update(
          day,
          (value) => value + record.totalBytes,
          ifAbsent: () => record.totalBytes,
        );
      }

      var unmappedDevice = 0;

      for (final entry in effectiveRecords.entries) {
        final deviceBytes = entry.value
            .where(
              (record) => record.recordScope == UsageRecordScope.deviceTotal,
            )
            .fold<int>(0, (sum, record) => sum + record.totalBytes);

        if (deviceBytes <= 0) continue;

        final difference = deviceBytes - (appBytesByDay[entry.key] ?? 0);

        if (difference > 0) {
          unmappedDevice += difference;
        }
      }

      // Hitung planner.
      PlannerResult? plannerResult;
      var unavailable = false;

      try {
        plannerResult = _planner(
          package: active,
          totalUsedBytes: totalUsed,
          todayUsedBytes: todayUsed,
          today: today,
        );
      } on UnimplementedError {
        unavailable = true;
      } catch (_) {
        unavailable = true;
      }

      // Evaluasi alert jika planner berhasil.
      if (plannerResult != null) {
        try {
          await _alertService.evaluateAndNotify(userId, active, plannerResult);
        } catch (_) {
          // Kegagalan alert tidak boleh merusak Dashboard.
        }
      }

      // Evaluasi batas penggunaan harian. Bila pengguna belum mengatur batas
      // manual, target harian Data Planner dipakai sebagai fallback sehingga
      // Dashboard dan notifikasi memakai angka batas yang sama.
      final loadedDataLimit = DashboardDataLimitCalculator.evaluate(
        limitSetting,
        todayUsed,
        plannerDailyTargetBytes: plannerResult?.dailyTargetBytes,
      );

      // Data Limit Warning memakai angka pemakaian yang sama dengan Dashboard.
      // Notifikasi deduplikasi per paket, tanggal, dan ambang.
      final limitNotifier = dataLimitService;
      if (limitNotifier != null) {
        try {
          await limitNotifier.evaluateAndNotify(
            packageId: packageId,
            userId: userId,
            usedBytes: todayUsed,
            plannerResult: plannerResult,
          );
        } catch (_) {
          // Kegagalan notifikasi tidak boleh menggagalkan Dashboard.
        }
      }

      if (gen != _generation) return;

      // Perbarui seluruh state setelah proses pemuatan selesai.
      package = active;
      records = loadedRecords;

      categoryUsage = loadedCategoryUsage;
      unclassifiedAppBytes = unclassifiedApp;
      unmappedDeviceBytes = unmappedDevice;

      dataLimit = loadedDataLimit;
      dailyUsage = loadedDaily;
      totalUsedBytes = totalUsed;

      plan = plannerResult;
      planUnavailable = unavailable;

      errorMessage = null;
      loadState = DashboardLoad.ready;

      _notify();
    } on AppException catch (e) {
      if (gen != _generation) return;

      errorMessage = e.message;
      loadState = DashboardLoad.error;

      _notify();
    } catch (_) {
      if (gen != _generation) return;

      errorMessage = 'Terjadi kesalahan saat memuat Dashboard.';
      loadState = DashboardLoad.error;

      _notify();
    }
  }

  Future<void> recheckPermission() async {
    final granted = await _usageService.hasPermission();

    if (granted != hasPermission) {
      hasPermission = granted;
      _notify();
    }
  }

  Future<void> openUsageAccessSettings() {
    return _usageService.openUsageAccessSettings();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
