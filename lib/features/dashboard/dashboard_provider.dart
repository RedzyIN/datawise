// PEMILIK: Anggota D. Menggabungkan paket + pemakaian + kategori + planner.
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/alert_service.dart';
import '../../services/data_limit_service.dart';
import '../../services/planner_service.dart';
import '../../services/usage_service.dart';
import '../../services/usage_sync_service.dart';

enum DashboardLoad { loading, ready, noPackage, error }

/// Pemakaian satu kategori kuota: kapasitas dari database, pemakaian dari
/// alokasi yang benar-benar tersimpan.
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
  }) : _usageRepo = usageRepo,
       _usageService = usageService,
       _sync = syncService ?? UsageSyncServiceImpl(usageService, usageRepo);

  final PackageRepository _packageRepo;
  final UsageRepository _usageRepo;
  final UsageService _usageService;
  final AlertService _alertService;
  final QuotaCategoryRepository? categoryRepo;
  final DataLimitRepository? dataLimitRepo;
  final UsageSyncService _sync;

  DashboardLoad loadState = DashboardLoad.loading;
  DataPackage? package;
  PlannerResult? plan;
  List<UsageRecord> records = const [];

  /// Kategori kuota paket aktif beserta pemakaian hasil alokasi.
  List<CategoryUsage> categoryUsage = const [];

  /// Pemakaian yang tersimpan tetapi belum/tidak dapat dialokasikan ke kategori.
  ///
  /// Agregat perangkat (DEVICE_TOTAL) memang tidak dialokasikan karena Android
  /// tidak memberi rincian per aplikasi, jadi angkanya tetap dihitung di sini
  /// dan tidak disamarkan ke kategori mana pun.
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

  /// Memilih satu sumber penggunaan efektif untuk setiap tanggal.
  ///
  /// Prioritas:
  /// 1. MANUAL_TOTAL jika tersedia.
  /// 2. DEVICE_TOTAL jika tersedia.
  /// 3. APP_USAGE jika DEVICE_TOTAL tidak tersedia.
  ///
  /// DEVICE_TOTAL dan APP_USAGE tidak pernah dijumlahkan bersamaan.
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
    syncMessage = null;
    lastSync = null;
    lastReading = null;
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
        } catch (_) {}
      }

      hasPermission = await _usageService.hasPermission();
      if (gen != _generation) return;

      if (hasPermission) {
        // Pembacaan Android disimpan/diperbarui ke SQLite sebelum Dashboard
        // membaca ulang. Angka di layar selalu berasal dari repository.
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
      final categories = categorySource == null
          ? const <QuotaCategory>[]
          : await categorySource.getByPackage(packageId);
      if (gen != _generation) return;

      final limitSetting = await dataLimitRepo?.getByPackage(packageId);
      if (gen != _generation) return;

      final effective = _buildEffectiveRecords(loadedRecords);
      final loadedDaily = {
        for (final entry in effective.entries)
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

      final allocatedByCategory = <String, int>{};
      final allocatedByRecord = <String, int>{};

      for (final allocation in allocations) {
        allocatedByRecord[allocation.usageRecordId] =
            (allocatedByRecord[allocation.usageRecordId] ?? 0) +
            allocation.allocatedBytes;

        final categoryId = allocation.quotaCategoryId;
        if (categoryId != null) {
          allocatedByCategory[categoryId] =
              (allocatedByCategory[categoryId] ?? 0) +
              allocation.allocatedBytes;
        }
      }

      var unallocated = 0;
      for (final dayRecords in effective.values) {
        for (final record in dayRecords) {
          final allocated = record.id == null
              ? 0
              : (allocatedByRecord[record.id!] ?? 0);
          final remainder = record.totalBytes - allocated;

          if (remainder > 0) unallocated += remainder;
        }
      }

      final loadedCategoryUsage = [
        for (final category in categories)
          CategoryUsage(
            category: category,
            usedBytes: category.id == null
                ? 0
                : (allocatedByCategory[category.id!] ?? 0),
          ),
      ];

      PlannerResult? result;
      var unavailable = false;

      try {
        result = PlannerService.calculate(
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

      if (result != null) {
        try {
          await _alertService.evaluateAndNotify(userId, active, result);
        } catch (_) {
          // Kegagalan notifikasi tidak boleh merusak Dashboard.
        }
      }

      if (gen != _generation) return;

      package = active;
      records = loadedRecords;
      categoryUsage = loadedCategoryUsage;
      unclassifiedBytes = unallocated;
      dataLimit = DataLimitService.evaluate(limitSetting, todayUsed);
      dailyUsage = loadedDaily;
      totalUsedBytes = totalUsed;
      plan = result;
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

  Future<void> openUsageAccessSettings() =>
      _usageService.openUsageAccessSettings();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
