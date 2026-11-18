import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/alert_service.dart';
import '../../services/planner_service.dart';
import '../../services/usage_service.dart';

enum DashboardLoad { loading, ready, noPackage, error }

class DashboardProvider extends ChangeNotifier {
  DashboardProvider(
    this._packageRepo,
    this._usageRepo,
    this._usageService,
    this._alertService,
  );

  final PackageRepository _packageRepo;
  final UsageRepository _usageRepo;
  final UsageService _usageService;
  final AlertService _alertService;

  DashboardLoad loadState = DashboardLoad.loading;
  DataPackage? package;
  PlannerResult? plan;
  List<UsageRecord> records = const [];

  Map<DateTime, int> dailyUsage = const {};
  String? errorMessage;

  int totalUsedBytes = 0;
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
  Map<DateTime, int> _buildDailyUsage(List<UsageRecord> sourceRecords) {
    final grouped = <DateTime, List<UsageRecord>>{};

    for (final record in sourceRecords) {
      if (record.networkType == NetworkType.wifi) continue;

      final day = dateOnly(record.periodStartAt);
      grouped.putIfAbsent(day, () => []).add(record);
    }

    final result = <DateTime, int>{};

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

      result[entry.key] = total;
    }

    return result;
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
        dailyUsage = const {};
        totalUsedBytes = 0;
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

      hasPermission = await _usageService.hasPermission();

      if (hasPermission) {
        final reading = await _usageService.refreshToday(active);
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

      final loadedDaily = _buildDailyUsage(loadedRecords);

      final totalUsed = loadedDaily.values.fold<int>(
        0,
        (sum, bytes) => sum + bytes,
      );

      final todayUsed = loadedDaily[today] ?? 0;

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
