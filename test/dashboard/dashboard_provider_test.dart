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
  Future<UsageReading> readMobileUsage(DateTime s, DateTime e) async => refreshToday(
      DataPackage(
          userId: 'x', name: 'x', operator: 'x', totalBytes: 1, initialUsedBytes: 0,
          startDate: s, endDate: e, price: null, isActive: true,
          createdAt: s, updatedAt: s));
  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    final now = DateTime.now();
    return UsageReading(
        status: UsageReadStatus.ok,
        totalBytes: 0,
        start: dateOnly(now),
        end: now,
        message: null);
  }
}

class _FakeAlertService implements AlertService {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> evaluateAndNotify(DataPackage package, PlannerResult result) async {}
}

void main() {
  late InMemoryPackageRepository packages;
  late InMemoryUsageRepository usage;

  DataPackage pkg(String uid, {bool active = true}) {
    final now = DateTime.now();
    return DataPackage(
      userId: uid,
      name: 'Paket Bulanan',
      operator: 'Telkomsel',
      totalBytes: 25 * kBytesPerGBForTest,
      initialUsedBytes: 1 * kBytesPerGBForTest,
      startDate: dateOnly(now.subtract(const Duration(days: 2))),
      endDate: dateOnly(now.add(const Duration(days: 20))),
      price: null,
      isActive: active,
      createdAt: now,
      updatedAt: now,
    );
  }

  DashboardProvider build({required bool granted}) => DashboardProvider(
        packages, usage, _FakeUsageService(granted), _FakeAlertService());

  setUp(() {
    packages = InMemoryPackageRepository();
    usage = InMemoryUsageRepository(packages);
  });

  test('tanpa paket aktif -> noPackage', () async {
    final d = build(granted: false);
    await d.refresh('uid_1');
    expect(d.loadState, DashboardLoad.noPackage);
    expect(d.package, isNull);
  });

  test('memuat paket aktif nyata dari repository + total terpakai', () async {
    final id = await packages.add(pkg('uid_1'));
    await usage.upsertRecord(id, DateTime.now(), 500000000, UsageSource.auto);

    final d = build(granted: true);
    await d.refresh('uid_1');

    expect(d.loadState, DashboardLoad.ready);
    expect(d.package?.name, 'Paket Bulanan');
    expect(d.totalUsedBytes, 1 * kBytesPerGBForTest + 500000000);
    expect(d.hasPermission, isTrue);
    expect(d.lastUpdatedAt, isNotNull);
  });

  test('data akun lain tidak tampil', () async {
    await packages.add(pkg('uid_A'));
    final d = build(granted: false);
    await d.refresh('uid_B');
    expect(d.loadState, DashboardLoad.noPackage);
  });

  test('manual menggantikan auto pada tanggal yang sama (tidak dijumlahkan)', () async {
    final id = await packages.add(pkg('uid_1'));
    final today = dateOnly(DateTime.now());
    await usage.upsertRecord(id, today, 300000000, UsageSource.auto);
    await usage.upsertRecord(id, today, 700000000, UsageSource.manual);

    final d = build(granted: true);
    await d.refresh('uid_1');

    expect(d.dailyUsage[today], 700000000);
    expect(d.totalUsedBytes, 1 * kBytesPerGBForTest + 700000000);
  });

  test('dailyUsage memuat beberapa hari untuk grafik 7 hari', () async {
    final id = await packages.add(pkg('uid_1'));
    final today = dateOnly(DateTime.now());
    for (var i = 0; i < 3; i++) {
      await usage.upsertRecord(
          id, today.subtract(Duration(days: i)), (i + 1) * 100000000, UsageSource.auto);
    }
    final d = build(granted: true);
    await d.refresh('uid_1');
    expect(d.dailyUsage.length, 3);
    expect(d.dailyUsage[today.subtract(const Duration(days: 2))], 300000000);
  });

  test('PlannerService belum selesai -> tetap ready, plan null, paket tetap tampil',
      () async {
    await packages.add(pkg('uid_1'));
    final d = build(granted: true);
    await d.refresh('uid_1');
    // Selama PlannerService masih UnimplementedError (Anggota B).
    expect(d.loadState, DashboardLoad.ready);
    expect(d.package, isNotNull);
    if (d.plan == null) expect(d.planUnavailable, isTrue);
  });

  test('izin belum diberikan -> hasPermission false, tidak ada lastUpdatedAt', () async {
    await packages.add(pkg('uid_1'));
    final d = build(granted: false);
    await d.refresh('uid_1');
    expect(d.hasPermission, isFalse);
    expect(d.lastUpdatedAt, isNull);
  });
}

const int kBytesPerGBForTest = 1000000000;
