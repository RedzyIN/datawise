// PEMILIK: Anggota D. Menggabungkan paket + kategori + pemakaian + planner + alert.
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/alert_service.dart';
import '../../services/planner_service.dart';
import '../../services/usage_service.dart';

enum DashboardLoad { loading, ready, noPackage, error }

/// Fungsi planner yang dapat diganti saat pengujian.
///
/// Kontrak aslinya tetap [PlannerService.calculate] milik Anggota B; Dashboard
/// hanya menampilkan hasilnya dan tidak menghitung target sendiri.
typedef DashboardPlanner = PlannerResult Function({
  required DataPackage package,
  required int totalUsedBytes,
  required int todayUsedBytes,
  required DateTime today,
});

/// Ringkasan satu kategori kuota untuk Dashboard.
///
/// Nilai [usedBytes] berasal dari alokasi pemakaian yang tersimpan di repository,
/// sehingga UI tidak perlu (dan tidak boleh) menghitung ulang alokasi kategori.
class DashboardCategorySummary {
  const DashboardCategorySummary({
    required this.id,
    required this.name,
    required this.capacityBytes,
    required this.usedBytes,
    required this.isMain,
  });

  final String id;
  final String name;
  final int capacityBytes;
  final int usedBytes;
  final bool isMain;

  int get remainingBytes =>
      capacityBytes - usedBytes < 0 ? 0 : capacityBytes - usedBytes;
}

/// Satu tanggal hanya memakai satu sumber pemakaian efektif.
class _EffectiveUsage {
  const _EffectiveUsage(this.daily, this.recordIds);

  final Map<DateTime, int> daily;
  final Set<String> recordIds;
}

class DashboardProvider extends ChangeNotifier {
  DashboardProvider(
    this._packageRepo,
    this._categoryRepo,
    this._usageRepo,
    this._usageService,
    this._alertService, {
    DashboardPlanner? planner,
  }) : _planner = planner ?? PlannerService.calculate;

  final PackageRepository _packageRepo;
  final QuotaCategoryRepository _categoryRepo;
  final UsageRepository _usageRepo;
  final UsageService _usageService;
  final AlertService _alertService;
  final DashboardPlanner _planner;

  DashboardLoad loadState = DashboardLoad.loading;
  DataPackage? package;
  PlannerResult? plan;
  List<UsageRecord> records = const [];
  List<DashboardCategorySummary> categories = const [];

  Map<DateTime, int> dailyUsage = const {};
  String? errorMessage;

  int totalUsedBytes = 0;

  /// Pemakaian efektif yang belum memiliki alokasi kategori.
  int unallocatedBytes = 0;

  bool hasPermission = false;
  UsageReading? lastReading;
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
  _EffectiveUsage _buildEffectiveUsage(List<UsageRecord> sourceRecords) {
    final grouped = <DateTime, List<UsageRecord>>{};

    for (final record in sourceRecords) {
      if (record.networkType == NetworkType.wifi) continue;

      final day = dateOnly(record.periodStartAt);
      grouped.putIfAbsent(day, () => []).add(record);
    }

    final daily = <DateTime, int>{};
    final recordIds = <String>{};

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

      final total = selectedRecords.fold<int>(
        0,
        (sum, record) => sum + record.totalBytes,
      );

      daily[entry.key] = total;

      for (final record in selectedRecords) {
        final id = record.id;
        if (id != null) recordIds.add(id);
      }
    }

    return _EffectiveUsage(daily, recordIds);
  }

  /// Sisa kategori dihitung dari alokasi pada catatan pemakaian efektif saja.
  List<DashboardCategorySummary> _buildCategorySummaries(
    List<QuotaCategory> sourceCategories,
    List<UsageAllocation> allocations,
    Set<String> effectiveRecordIds,
  ) {
    final usedByCategory = <String, int>{};

    for (final allocation in allocations) {
      if (!effectiveRecordIds.contains(allocation.usageRecordId)) continue;

      final categoryId = allocation.quotaCategoryId;
      if (categoryId == null) continue;

      usedByCategory.update(
        categoryId,
        (value) => value + allocation.allocatedBytes,
        ifAbsent: () => allocation.allocatedBytes,
      );
    }

    return [
      for (final category in sourceCategories)
        if (category.id != null)
          DashboardCategorySummary(
            id: category.id!,
            name: category.categoryName,
            capacityBytes: category.capacityBytes,
            usedBytes: usedByCategory[category.id] ?? 0,
            isMain: category.categoryType == QuotaCategoryType.main,
          ),
    ];
  }

  int _buildUnallocatedBytes(
    List<UsageAllocation> allocations,
    Set<String> effectiveRecordIds,
    int totalUsed,
  ) {
    final allocated = allocations
        .where(
          (allocation) =>
              effectiveRecordIds.contains(allocation.usageRecordId) &&
              allocation.quotaCategoryId != null,
        )
        .fold<int>(0, (sum, allocation) => sum + allocation.allocatedBytes);

    final unallocated = totalUsed - allocated;
    return unallocated < 0 ? 0 : unallocated;
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
        package = null;
        plan = null;
        records = const [];
        categories = const [];
        dailyUsage = const {};
        totalUsedBytes = 0;
        unallocatedBytes = 0;
        planUnavailable = false;
        errorMessage = null;

        hasPermission = await _usageService.hasPermission();

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

      UsageReading? reading;

      hasPermission = await _usageService.hasPermission();

      if (hasPermission) {
        reading = await _usageService.refreshToday(active);
        lastReading = reading;

        if (reading.status == UsageReadStatus.ok) {
          lastUpdatedAt = DateTime.now();
        }
      } else {
        lastReading = null;
      }

      if (gen != _generation) return;

      final today = dateOnly(DateTime.now());

      final loadedRecords = await _usageRepo.getRecords(packageId);

      if (gen != _generation) return;

      final effectiveUsage = _buildEffectiveUsage(loadedRecords);

      var dailyView = effectiveUsage.daily;

      var totalUsed = effectiveUsage.daily.values.fold<int>(
        0,
        (sum, bytes) => sum + bytes,
      );

      var todayUsed = effectiveUsage.daily[today] ?? 0;

      // Statistik perangkat hari ini dipakai sebagai angka sementara bila
      // belum ada catatan pemakaian tersimpan untuk hari ini. Catatan manual
      // (atau auto) tetap menang, sesuai aturan pemakaian efektif kontrak data.
      final todayStats = reading != null && reading.status == UsageReadStatus.ok
          ? reading.totalBytes
          : 0;

      if (todayStats > 0 && !effectiveUsage.daily.containsKey(today)) {
        dailyView = {...effectiveUsage.daily, today: todayStats};
        totalUsed += todayStats;
        todayUsed = todayStats;
      }

      List<QuotaCategory> loadedCategories = const [];
      List<UsageAllocation> loadedAllocations = const [];

      try {
        loadedCategories = await _categoryRepo.getByPackage(packageId);
      } catch (_) {
        // Kategori yang gagal dimuat tidak boleh menggagalkan seluruh Dashboard.
        loadedCategories = const [];
      }

      try {
        loadedAllocations = await _usageRepo.getAllocationsByPackage(packageId);
      } catch (_) {
        loadedAllocations = const [];
      }

      if (gen != _generation) return;

      PlannerResult? result;
      var unavailable = false;

      try {
        result = _planner(
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

      totalUsedBytes = totalUsed;

      package = active;
      records = loadedRecords;
      dailyUsage = dailyView;
      categories = _buildCategorySummaries(
        loadedCategories,
        loadedAllocations,
        effectiveUsage.recordIds,
      );
      unallocatedBytes = _buildUnallocatedBytes(
        loadedAllocations,
        effectiveUsage.recordIds,
        totalUsed,
      );
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
