// PEMILIK: Anggota D. Menggabungkan paket + pemakaian + planner + alert.
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
  bool hasUsagePermission = false;
  bool isRefreshing = false;
  DateTime? lastUpdatedAt;
  String? errorMessage;

  int get totalUsedBytes => plan?.usedBytes ??
      (package == null
          ? 0
          : records.fold<int>(package!.initialUsedBytes,
              (sum, record) => sum + record.usedBytes));
  int get remainingBytes =>
      package == null ? 0 : (package!.totalBytes - totalUsedBytes).clamp(0, package!.totalBytes).toInt();
  int get todayUsedBytes {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return dailyUsage[today] ?? 0;
  }

  Future<void> refresh(String userId) async {
    if (isRefreshing) return;
    isRefreshing = true;
    errorMessage = null;
    if (loadState != DashboardLoad.ready) loadState = DashboardLoad.loading;
    notifyListeners();

    try {
      final activePackage = await _packageRepo.getActive(userId);
      package = activePackage;
      if (activePackage == null) {
        plan = null;
        records = const [];
        dailyUsage = const {};
        hasUsagePermission = await _usageService.hasPermission();
        loadState = DashboardLoad.noPackage;
        lastUpdatedAt = DateTime.now();
        return;
      }

      hasUsagePermission = await _usageService.hasPermission();
      // Service tidak melempar error; status permission/unsupported ditangani di UI.
      await _usageService.refreshToday(activePackage);

      final id = activePackage.id;
      if (id == null) {
        throw const AppException(
          AppException.validation,
          'ID paket aktif belum tersedia.',
        );
      }

      final results = await Future.wait<Object>([
        _usageRepo.getTotalUsedBytes(id),
        _usageRepo.getUsedBytesOn(id, DateTime.now()),
        _usageRepo.getRecords(id),
        _usageRepo.getDailyUsage(id),
      ]);
      final totalUsed = results[0] as int;
      final todayUsed = results[1] as int;
      records = results[2] as List<UsageRecord>;
      dailyUsage = results[3] as Map<DateTime, int>;

      try {
        plan = PlannerService.calculate(
          package: activePackage,
          totalUsedBytes: totalUsed,
          todayUsedBytes: todayUsed,
          today: DateTime.now(),
        );
        await _alertService.evaluateAndNotify(activePackage, plan!);
      } on UnimplementedError {
        // Planner dan alert masih dikerjakan anggota pemiliknya.
        plan = null;
      }

      lastUpdatedAt = DateTime.now();
      loadState = DashboardLoad.ready;
    } catch (e) {
      errorMessage = e is AppException ? e.message : 'Gagal memuat Dashboard: $e';
      loadState = DashboardLoad.error;
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }
}
