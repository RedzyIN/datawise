import 'package:datawise/features/auth/auth_provider.dart';
import 'package:datawise/features/dashboard/dashboard_page.dart';
import 'package:datawise/features/dashboard/dashboard_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);

  final AppUser? _user;

  @override
  AppUser? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Usage implements UsageService {
  _Usage(this.granted);

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

class _Alert implements AlertService {
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

Widget _app(AuthProvider auth, DashboardProvider dashboard) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<DashboardProvider>.value(value: dashboard),
    ],
    child: const MaterialApp(home: DashboardPage()),
  );
}

Future<void> _addDeviceUsage(
  InMemoryUsageRepository repository,
  String packageId,
  DateTime date,
  int bytes,
) async {
  final start = dateOnly(date);

  await repository.upsertRecord(
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

void main() {
  const user = AppUser(uid: 'u1', email: 'sarah@mail.com');

  testWidgets('tanpa login menampilkan Dashboard dengan data contoh', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packageRepo = InMemoryPackageRepository();
    final dashboard = DashboardProvider(
      packageRepo,
      InMemoryUsageRepository(packageRepo),
      _Usage(false),
      _Alert(),
    );

    await tester.pumpWidget(_app(_FakeAuth(null), dashboard));
    await tester.pumpAndSettle();

    expect(find.text('Halo, Sarah!'), findsOneWidget);
    expect(find.text('18,40 GB'), findsOneWidget);
    expect(find.text('39% terpakai'), findsOneWidget);
    expect(find.text('Pemakaian 7 Hari Terakhir'), findsOneWidget);
    expect(find.text('Masukkan Pemakaian'), findsOneWidget);
    expect(find.text('Detail Aplikasi'), findsOneWidget);
    expect(find.text('Beli Paket Ekstra'), findsNothing);
    expect(find.text('Sisa per Kategori'), findsOneWidget);
    expect(find.text('Kuota Malam'), findsOneWidget);
    expect(find.text('Kuota Sosial'), findsOneWidget);

    dashboard.dispose();
  });

  testWidgets('tanpa paket aktif menampilkan ajakan tambah paket', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packageRepo = InMemoryPackageRepository();
    final dashboard = DashboardProvider(
      packageRepo,
      InMemoryUsageRepository(packageRepo),
      _Usage(false),
      _Alert(),
    );

    await tester.pumpWidget(_app(_FakeAuth(user), dashboard));
    await tester.pumpAndSettle();

    expect(find.text('Halo, Sarah!'), findsOneWidget);
    expect(find.text('Belum ada paket aktif'), findsOneWidget);
    expect(find.text('Tambah Paket'), findsOneWidget);

    dashboard.dispose();
  });

  testWidgets('paket nyata tampil di Dashboard bersama status izin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packageRepo = InMemoryPackageRepository();
    final usageRepo = InMemoryUsageRepository(packageRepo);

    final now = DateTime.now();

    final id = await packageRepo.add(
      DataPackage(
        userId: 'u1',
        packageName: 'Paket Bulanan 30 GB',
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 30000000000,
        startDate: dateOnly(now.subtract(const Duration(days: 5))),
        endDate: dateOnly(now.add(const Duration(days: 25))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _addDeviceUsage(usageRepo, id, now, 900000000);

    final dashboard = DashboardProvider(
      packageRepo,
      usageRepo,
      _Usage(false),
      _Alert(),
    );

    await tester.pumpWidget(_app(_FakeAuth(user), dashboard));
    await tester.pumpAndSettle();

    expect(find.textContaining('Paket Bulanan 30 GB'), findsOneWidget);
    expect(find.text('Izin belum diberikan'), findsOneWidget);
    expect(find.text('Masukkan Pemakaian'), findsOneWidget);

    dashboard.dispose();
  });
}
