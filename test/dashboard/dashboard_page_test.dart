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
  Future<UsageReading> readMobileUsage(DateTime s, DateTime e) async => _r();
  @override
  Future<UsageReading> refreshToday(DataPackage package) async => _r();
  UsageReading _r() => UsageReading(
      status: UsageReadStatus.ok,
      totalBytes: 0,
      start: DateTime.now(),
      end: DateTime.now(),
      message: null);
}

class _Alert implements AlertService {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> evaluateAndNotify(DataPackage package, PlannerResult result) async {}
}

Widget _app(AuthProvider auth, DashboardProvider dash) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<DashboardProvider>.value(value: dash),
      ],
      child: const MaterialApp(home: DashboardPage()),
    );

void main() {
  const user = AppUser(uid: 'u1', email: 'sarah@mail.com');

  // Pekan 1: tanpa sesi login, Dashboard tetap tampil persis desain (data contoh).
  testWidgets('tanpa login -> tampil data contoh sesuai desain Figma', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final pkgRepo = InMemoryPackageRepository();
    final dash = DashboardProvider(
        pkgRepo, InMemoryUsageRepository(pkgRepo), _Usage(false), _Alert());
    await t.pumpWidget(_app(_FakeAuth(null) as AuthProvider, dash));
    await t.pumpAndSettle();

    expect(find.text('Halo, Sarah!'), findsOneWidget);
    expect(find.text('18,40 GB'), findsOneWidget);
    expect(find.text('39% terpakai'), findsOneWidget);
    expect(find.text('Pemakaian 7 Hari Terakhir'), findsOneWidget);
    expect(find.text('Masukkan Pemakaian'), findsOneWidget);
    expect(find.text('Detail Aplikasi'), findsOneWidget);
    expect(find.text('Beli Paket Ekstra'), findsOneWidget);
    expect(find.text('Sisa per Kategori'), findsOneWidget);
    expect(find.text('Kuota Malam'), findsOneWidget);
    expect(find.text('Kuota Sosial'), findsOneWidget);
  });

  testWidgets('tanpa paket aktif menampilkan ajakan tambah paket', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final pkgRepo = InMemoryPackageRepository();
    final dash = DashboardProvider(
        pkgRepo, InMemoryUsageRepository(pkgRepo), _Usage(false), _Alert());
    await t.pumpWidget(_app(_FakeAuth(user) as AuthProvider, dash));
    await t.pumpAndSettle();

    expect(find.text('Halo, Sarah!'), findsOneWidget);
    expect(find.text('Belum ada paket aktif'), findsOneWidget);
  });

  testWidgets('paket nyata dari repository tampil di Beranda + status izin', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final pkgRepo = InMemoryPackageRepository();
    final usageRepo = InMemoryUsageRepository(pkgRepo);
    final now = DateTime.now();
    final id = await pkgRepo.add(DataPackage(
      userId: 'u1',
      name: 'Paket Bulanan 30 GB',
      operator: 'Telkomsel',
      totalBytes: 30000000000,
      initialUsedBytes: 0,
      startDate: dateOnly(now.subtract(const Duration(days: 5))),
      endDate: dateOnly(now.add(const Duration(days: 25))),
      price: null,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    ));
    await usageRepo.upsertRecord(id, now, 900000000, UsageSource.auto);

    final dash = DashboardProvider(pkgRepo, usageRepo, _Usage(false), _Alert());
    await t.pumpWidget(_app(_FakeAuth(user) as AuthProvider, dash));
    await t.pumpAndSettle();

    expect(find.textContaining('Paket Bulanan 30 GB'), findsOneWidget);
    expect(find.text('Izin belum diberikan'), findsOneWidget);
    expect(find.text('Masukkan Pemakaian'), findsOneWidget);
  });
}

