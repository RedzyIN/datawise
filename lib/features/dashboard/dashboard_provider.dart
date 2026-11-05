// PEMILIK: Anggota D. Menggabungkan paket + pemakaian + planner + alert.
// TODO(D): refresh() mengikuti urutan: getActive -> refreshToday -> getTotalUsedBytes
// & getUsedBytesOn -> PlannerService.calculate -> evaluateAndNotify -> notifyListeners.
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/alert_service.dart';
import '../../services/usage_service.dart';

enum DashboardLoad { loading, ready, noPackage, error }

class DashboardProvider extends ChangeNotifier {
  DashboardProvider(
    this._packageRepo,
    this._usageRepo,
    this._usageService,
    this._alertService,
  );

  // ignore: unused_field
  final PackageRepository _packageRepo;
  // ignore: unused_field
  final UsageRepository _usageRepo;
  // ignore: unused_field
  final UsageService _usageService;
  // ignore: unused_field
  final AlertService _alertService;

  DashboardLoad loadState = DashboardLoad.loading;
  DataPackage? package;
  PlannerResult? plan;
  List<UsageRecord> records = const [];
  String? errorMessage;

  Future<void> refresh(String userId) async {}
}
