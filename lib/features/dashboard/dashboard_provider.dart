// PEMILIK: Anggota D. Menggabungkan paket, pemakaian, kategori, planner, dan alert.

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/alert_service.dart';
import '../../services/data_limit_service.dart';
import '../../services/planner_service.dart';
import '../../services/usage_service.dart';
import '../../services/usage_sync_service.dart';

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
    UsageSyncService? syncService,
    DashboardPlanner? planner,
  }) : _usageRepo = usageRepo,
       _usageService = usageService,
       _sync = syncService ?? UsageSyncServiceImpl(usageService, usageRepo),
       _planner = planner ?? PlannerService.calculate;

  final PackageRepository _packageRepo;
  final UsageRepository _usageRepo;
  final UsageService _usageService;
  final AlertService _alertService;

  final QuotaCategoryRepository? categoryRepo;
  final DataLimitRepository? dataLimitRepo;

  final UsageSyncService _sync;
  final DashboardPlanner _planner;

  DashboardLoad loadState = DashboardLoad.loading;

  DataPackage? package;
  PlannerResult? plan;
  List<UsageRecord> records = const [];

  List<CategoryUsage> categoryUsage = const [];
  int unclassifiedBytes = 0;

  DataLimitStatus dataLimit = DataLimitStatus.none;

  Map<DateTime, int> dailyUsage = const {};
  String? errorMessage;

  int totalUsedBytes = 0;

  bool hasPermission = false;
  UsageReading? lastReading;
  UsageSyncResult? lastSync;
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
    final grouped = <DateTime, List<UsageRecord>>{};

    for (final record in sourceRecords) {
      if (record.networkType == NetworkType.wifi) continue;

      final day = dateOnly(record.periodStartAt);
      grouped.putIfAbsent(day, () => []).add(record);
    }

    final result = <DateTime, List<UsageRecord>>{};

    for (final entry in grouped.entries) {
      final dayRecords = entry.value;

      final manualRecords = dayRecords.where(
        (record) =>
            record.source == UsageSource.manual &&
            record.recordScope == UsageRecordScope.manualTotal,
      );

      final deviceRecords = dayRecords.where(
        (record) =>
            record.source == UsageSource.android &&
            record.recordScope == UsageRecordScope.deviceTotal,
      );

      final appRecords = dayRecords.where(
        (record) =>
            record.source == UsageSource.android &&
            record.recordScope == UsageRecordScope.appUsage,
      );

      final Iterable<UsageRecord> selectedRecords;

      if (manualRecords.isNotEmpty) {
        selectedRecords = manualRecords;
      } else if (deviceRecords.isNotEmpty) {
        selectedRecords = deviceRecords;
      } else {
        selectedRecords = appRecords;
      }

      result[entry.key] = selectedRecords.toList();
    }

    return result;
  }

  void _resetForNoPackage() {
    package = null;
    plan = null;
    records = const [];

    categoryUsage = const [];
    unclassifiedBytes = 0;
    dataLimit = DataLimitStatus.none;

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

        lastSync = sync;
        lastReading = sync.reading;
        syncMessage = sync.saved ? null : sync.message;

        if (sync.saved) {
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

      // Simpan ID catatan yang benar-benar digunakan dalam perhitungan.
      final effectiveRecordIds = <String>{
        for (final dayRecords in effectiveRecords.values)
          for (final record in dayRecords)
            if (record.id != null) record.id!,
      };

      // Hitung alokasi hanya dari catatan pemakaian efektif.
      final allocatedByCategory = <String, int>{};
      final allocatedByRecord = <String, int>{};

      for (final allocation in allocations) {
        if (!effectiveRecordIds.contains(allocation.usageRecordId)) {
          continue;
        }

        allocatedByRecord.update(
          allocation.usageRecordId,
          (value) => value + allocation.allocatedBytes,
          ifAbsent: () => allocation.allocatedBytes,
        );

        final categoryId = allocation.quotaCategoryId;

        if (categoryId != null) {
          allocatedByCategory.update(
            categoryId,
            (value) => value + allocation.allocatedBytes,
            ifAbsent: () => allocation.allocatedBytes,
          );
        }
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

      // Hitung pemakaian yang belum dialokasikan ke kategori.
      var unallocated = 0;

      for (final dayRecords in effectiveRecords.values) {
        for (final record in dayRecords) {
          final allocated = record.id == null
              ? 0
              : allocatedByRecord[record.id!] ?? 0;

          final remainder = record.totalBytes - allocated;

          if (remainder > 0) {
            unallocated += remainder;
          }
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

      if (gen != _generation) return;

      // Evaluasi batas penggunaan harian.
      final loadedDataLimit = DataLimitService.evaluate(
        limitSetting,
        todayUsed,
      );

      // Perbarui seluruh state setelah proses pemuatan selesai.
      package = active;
      records = loadedRecords;

      categoryUsage = loadedCategoryUsage;
      unclassifiedBytes = unallocated;

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
