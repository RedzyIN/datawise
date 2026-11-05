// PEMILIK: Anggota C. KONTRAK BEKU #4 & #5. TIDAK PERNAH MELEMPAR ERROR.
// TODO(C): isi UsageServiceImpl (MethodChannel 'datawise/usage').
import '../models/models.dart';
import '../repositories/repositories.dart';

abstract class UsageService {
  Future<bool> hasPermission();
  Future<void> openUsageAccessSettings();
  Future<void> openInternetSettings();
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end);

  /// Baca hari ini (00:00 sampai sekarang), lalu simpan sebagai record 'auto'.
  Future<UsageReading> refreshToday(DataPackage package);
}

class UsageServiceImpl implements UsageService {
  UsageServiceImpl(this._usageRepo, this._settingsRepo);

  // ignore: unused_field
  final UsageRepository _usageRepo;
  // ignore: unused_field
  final SettingsRepository _settingsRepo;

  UsageReading _unsupported(DateTime s, DateTime e) => UsageReading(
        status: UsageReadStatus.unsupported,
        totalBytes: 0,
        start: s,
        end: e,
        message: 'Belum diimplementasikan.',
      );

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<void> openInternetSettings() async {}

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async =>
      _unsupported(start, end);

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    final now = DateTime.now();
    return _unsupported(dateOnly(now), now);
  }
}
