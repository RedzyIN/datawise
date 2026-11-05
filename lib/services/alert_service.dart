// PEMILIK: Anggota D. KONTRAK BEKU #4 & #6.
// TODO(D): isi AlertServiceImpl dengan flutter_local_notifications.
import '../models/models.dart';
import '../repositories/repositories.dart';

abstract class AlertService {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> evaluateAndNotify(DataPackage package, PlannerResult result);
}

class AlertServiceImpl implements AlertService {
  AlertServiceImpl(this._alertRepo, this._settingsRepo);

  // ignore: unused_field
  final AlertRepository _alertRepo;
  // ignore: unused_field
  final SettingsRepository _settingsRepo;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> evaluateAndNotify(DataPackage package, PlannerResult result) async {}
}
