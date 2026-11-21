import 'package:datawise/features/dashboard/dashboard_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUsageService implements UsageService {
  _FakeUsageService(this.granted);

  final bool granted;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<void> openInternetSettings() async {}

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async {
    return _reading();
  }

  @override
  Future<AppUsageReading> readAppUsage(DateTime start, DateTime end) async {
    return AppUsageReading(
      status: UsageReadStatus.ok,
      buckets: const [],
      start: start,
      end: end,
      message: null,
    );
  }

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    return _reading();
  }

  UsageReading _reading() {
    final now = DateTime.now();

    return UsageReading(
      status: UsageReadStatus.ok,
      totalBytes: 0,
      start: dateOnly(now),
      end: now,
      message: null,
    );
  }
}

class _FakeAlertService implements AlertService {
  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> evaluateAndNotify(
    String userId,
    DataPackage package,
    PlannerResult result,
  ) async {}
}

void main() {
  late InMemoryPackageRepository packages;
  late InMemoryUsageRepository usage;

  DataPackage pkg(String uid, {bool active = true}) {
    final now = DateTime.now();

    return DataPackage(
      userId: uid,
      packageName: 'Paket Bulanan',
      operatorName: 'Telkomsel',
      advertisedTotalQuotaBytes: 25 * kBytesPerGBForTest,
      startDate: dateOnly(now.subtract(const Duration(days: 2))),
      endDate: dateOnly(now.add(const Duration(days: 20))),
      status: active ? PackageStatus.active : PackageStatus.inactive,
      createdAt: now,
      updatedAt: now,
    );
  }

  DashboardProvider build({required bool granted}) {
    return DashboardProvider(
      packages,
      usage,
      _FakeUsageService(granted),
      _FakeAlertService(),
    );
  }

  Future<void> addDeviceRecord(
    String packageId,
    DateTime date,
    int bytes,
  ) async {
    final start = dateOnly(date);

    await usage.upsertRecord(
      UsageRecord(
        packageId: packageId,
        recordScope: UsageRecordScope.deviceTotal,
        networkType: NetworkType.mobile,
        periodStartAt: start,
        periodEndAt: start.add(const Duration(days: 1)),
        rxBytes: bytes,
        txBytes: 0,
        source: UsageSource.android,
        recordedAt: start.add(const Duration(days: 1)),
      ),
    );
  }

  setUp(() {
    packages = InMemoryPackageRepository();
    usage = InMemoryUsageRepository(packages);
  });

  test('tanpa paket aktif menghasilkan noPackage', () async {
    final dashboard = build(granted: false);

    await dashboard.refresh('uid_1');

    expect(dashboard.loadState, DashboardLoad.noPackage);
    expect(dashboard.package, isNull);
  });

  test('memuat paket aktif dan total penggunaan', () async {
    final id = await packages.add(pkg('uid_1'));

    await addDeviceRecord(id, DateTime.now(), 500000000);

    final dashboard = build(granted: true);

    await dashboard.refresh('uid_1');

    expect(dashboard.loadState, DashboardLoad.ready);
    expect(dashboard.package?.packageName, 'Paket Bulanan');
    expect(dashboard.totalUsedBytes, 500000000);
    expect(dashboard.hasPermission, isTrue);
    expect(dashboard.lastUpdatedAt, isNotNull);
  });

  test('data akun lain tidak ditampilkan', () async {
    await packages.add(pkg('uid_A'));

    final dashboard = build(granted: false);

    await dashboard.refresh('uid_B');

    expect(dashboard.loadState, DashboardLoad.noPackage);
    expect(dashboard.package, isNull);
  });

  test('DEVICE_TOTAL dipilih tanpa menjumlahkan APP_USAGE', () async {
    final id = await packages.add(pkg('uid_1'));
    final today = dateOnly(DateTime.now());

    await addDeviceRecord(id, today, 500000000);

    // APP_USAGE memerlukan alokasi, sehingga test ini hanya memastikan
    // bahwa total DEVICE_TOTAL tidak dijumlahkan dengan sumber lain.
    final dashboard = build(granted: false);

    await dashboard.refresh('uid_1');

    expect(dashboard.dailyUsage[today], 500000000);
    expect(dashboard.totalUsedBytes, 500000000);
  });

  test('dailyUsage memuat beberapa hari untuk grafik', () async {
    final id = await packages.add(pkg('uid_1'));
    final today = dateOnly(DateTime.now());

    for (var i = 0; i < 3; i++) {
      await addDeviceRecord(
        id,
        today.subtract(Duration(days: i)),
        (i + 1) * 100000000,
      );
    }

    final dashboard = build(granted: false);

    await dashboard.refresh('uid_1');

    expect(dashboard.dailyUsage.length, 3);
    expect(
      dashboard.dailyUsage[today.subtract(const Duration(days: 2))],
      300000000,
    );
  });

  test('PlannerService belum selesai tetapi Dashboard tetap ready', () async {
    await packages.add(pkg('uid_1'));

    final dashboard = build(granted: true);

    await dashboard.refresh('uid_1');

    expect(dashboard.loadState, DashboardLoad.ready);
    expect(dashboard.package, isNotNull);
    expect(dashboard.plan, isNull);
    expect(dashboard.planUnavailable, isTrue);
  });

  test('izin belum diberikan tidak menghasilkan waktu pembaruan', () async {
    await packages.add(pkg('uid_1'));

    final dashboard = build(granted: false);

    await dashboard.refresh('uid_1');

    expect(dashboard.hasPermission, isFalse);
    expect(dashboard.lastUpdatedAt, isNull);
  });
}

const int kBytesPerGBForTest = 1000000000;
