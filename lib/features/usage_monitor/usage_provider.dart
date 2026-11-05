// PEMILIK: Anggota C. Anggota dibekukan di dokumen C bagian 11.4.
// TODO(C): implementasikan. Provider menangkap AppException -> errorMessage.
// Catatan: tanda tangan konstruktor belum dibekukan; sesuaikan bersama Arsitek.
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/usage_service.dart';

class UsageProvider extends ChangeNotifier {
  UsageProvider(this._service, this._usageRepo, this._packageRepo);

  // ignore: unused_field
  final UsageService _service;
  // ignore: unused_field
  final UsageRepository _usageRepo;
  // ignore: unused_field
  final PackageRepository _packageRepo;

  bool get hasPermission => false;
  bool get isLoading => false;
  UsageReading? get lastReading => null;
  DateTime? get lastRefresh => null;
  String? get errorMessage => null;

  Future<void> checkPermission() async {}
  Future<void> refresh(DataPackage package) async {}
  Future<void> saveManualToday(DataPackage p, int bytes) async {}
  Future<void> deleteManualToday(DataPackage p) async {}
  Future<void> setInitialUsed(DataPackage p, int bytes) async {}
  Future<void> openUsageAccessSettings() async {}
  Future<void> openInternetSettings() async {}
}
