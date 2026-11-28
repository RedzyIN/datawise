import 'package:datawise/features/alerts/alert_provider.dart';
import 'package:datawise/features/auth/auth_provider.dart';
import 'package:datawise/features/dashboard/dashboard_page.dart';
import 'package:datawise/features/dashboard/dashboard_provider.dart';
import 'package:datawise/features/usage_breakdown/usage_breakdown_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:datawise/services/app_usage_sync_service.dart';
import 'package:datawise/services/usage/usage_classification_service.dart';
import 'package:datawise/services/usage_breakdown_service.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:fl_chart/fl_chart.dart';
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
  Future<bool> openInternetSettings() async => true;

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

AppUsageSyncService _appUsageSync(
  InMemoryPackageRepository packages,
  InMemoryQuotaCategoryRepository categories,
  InMemoryUsageRepository usage,
  UsageService service,
) {
  final rules = InMemoryClassificationRuleRepository(packages, categories);

  return AppUsageSyncService(
    service,
    usage,
    UsageClassificationService(
      ruleRepository: rules,
      categoryRepository: categories,
      usageRepository: usage,
    ),
  );
}

Widget _app(
  AuthProvider auth,
  DashboardProvider dashboard, {
  AlertProvider? alerts,
  UsageBreakdownProvider? breakdown,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<DashboardProvider>.value(value: dashboard),
      if (breakdown != null)
        ChangeNotifierProvider<UsageBreakdownProvider>.value(value: breakdown),
      ChangeNotifierProvider<AlertProvider>(
        create: (_) =>
            alerts ??
            AlertProvider(
              InMemoryAlertRepository(InMemoryPackageRepository()),
              InMemoryPackageRepository(),
            ),
      ),
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
    final categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    final usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);

    final usageService = _Usage(false);

    final dashboard = DashboardProvider(
      packageRepo,
      usageRepo,
      usageService,
      _Alert(),
      categoryRepo: categoryRepo,
      syncService: _appUsageSync(
        packageRepo,
        categoryRepo,
        usageRepo,
        usageService,
      ),
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
    final categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    final usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);

    final usageService = _Usage(false);

    final dashboard = DashboardProvider(
      packageRepo,
      usageRepo,
      usageService,
      _Alert(),
      categoryRepo: categoryRepo,
      syncService: _appUsageSync(
        packageRepo,
        categoryRepo,
        usageRepo,
        usageService,
      ),
    );

    await tester.pumpWidget(_app(_FakeAuth(user), dashboard));
    await tester.pumpAndSettle();

    expect(find.text('Halo, Sarah!'), findsOneWidget);
    expect(find.text('Belum ada paket aktif'), findsOneWidget);
    expect(find.text('Tambah Paket'), findsOneWidget);

    dashboard.dispose();
  });

  testWidgets('target harian dan mingguan tampil saat planner tersedia', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packageRepo = InMemoryPackageRepository();
    final categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    final usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);

    final now = DateTime.now();

    await packageRepo.add(
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

    final usageService = _Usage(true);

    final dashboard = DashboardProvider(
      packageRepo,
      usageRepo,
      usageService,
      _Alert(),
      categoryRepo: categoryRepo,
      syncService: _appUsageSync(
        packageRepo,
        categoryRepo,
        usageRepo,
        usageService,
      ),
      planner:
          ({
            required DataPackage package,
            required int totalUsedBytes,
            required int todayUsedBytes,
            required DateTime today,
          }) {
            return PlannerResult(
              status: PlannerStatus.normal,
              totalBytes: package.advertisedTotalQuotaBytes,
              usedBytes: 500000000,
              remainingBytes: 29500000000,
              remainingDays: 25,
              dailyTargetBytes: 1000000000,
              weeklyTargetBytes: 7000000000,
              todayUsedBytes: 0,
              usagePercent:
                  (500000000 / package.advertisedTotalQuotaBytes) * 100,
              todayPercentOfTarget: 0,
            );
          },
    );

    await tester.pumpWidget(_app(_FakeAuth(user), dashboard));
    await tester.pumpAndSettle();

    expect(find.text('Target: 1,00 GB', findRichText: true), findsOneWidget);
    expect(find.text('7,00 GB'), findsOneWidget);
    expect(find.textContaining('belum tersedia'), findsNothing);

    dashboard.dispose();
  });

  testWidgets('paket nyata tampil di Dashboard bersama status izin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packageRepo = InMemoryPackageRepository();
    final categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    final usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);

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

    final usageService = _Usage(false);

    final dashboard = DashboardProvider(
      packageRepo,
      usageRepo,
      usageService,
      _Alert(),
      categoryRepo: categoryRepo,
      syncService: _appUsageSync(
        packageRepo,
        categoryRepo,
        usageRepo,
        usageService,
      ),
    );

    await tester.pumpWidget(_app(_FakeAuth(user), dashboard));
    await tester.pumpAndSettle();

    expect(find.textContaining('Paket Bulanan 30 GB'), findsOneWidget);
    expect(find.text('Izin belum diberikan'), findsOneWidget);
    expect(find.text('Sisa per Kategori'), findsOneWidget);
    expect(find.text('Kuota Utama'), findsOneWidget);
    expect(find.text('Masukkan Pemakaian'), findsOneWidget);

    dashboard.dispose();
  });

  testWidgets('ikon lonceng menampilkan jumlah alert belum dibaca', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packageRepo = InMemoryPackageRepository();
    final categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    final usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);
    final alertRepo = InMemoryAlertRepository(packageRepo);

    final now = DateTime.now();

    final packageId = await packageRepo.add(
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

    Future<void> seed(String type, String key, {bool isRead = false}) {
      return alertRepo.createIfAbsent(
        AlertLog(
          packageId: packageId,
          alertType: alertTypeToDb(AlertType.values.byName(type)),
          message: 'Pesan $type',
          dedupeKey: '$packageId:$key',
          triggeredAt: now,
          isRead: isRead,
        ),
      );
    }

    await seed('quota20', 'quota20:1');
    await seed('daily100', 'daily100:1');
    await seed('expiring1d', 'expiring1d:1', isRead: true);

    final alerts = AlertProvider(alertRepo, packageRepo);
    final usageService = _Usage(false);

    final dashboard = DashboardProvider(
      packageRepo,
      usageRepo,
      usageService,
      _Alert(),
      categoryRepo: categoryRepo,
      syncService: _appUsageSync(
        packageRepo,
        categoryRepo,
        usageRepo,
        usageService,
      ),
    );

    await tester.pumpWidget(_app(_FakeAuth(user), dashboard, alerts: alerts));
    await tester.pumpAndSettle();

    // Indikator mengikuti jumlah alert yang belum dibaca, bukan seluruh alert.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('header-bell-badge'))).data,
      '2',
    );

    await tester.tap(find.byKey(const ValueKey('header-bell')));
    await tester.pumpAndSettle();

    expect(find.text('Semua Notifikasi'), findsOneWidget);
    expect(find.text('2 belum dibaca • 3 notifikasi'), findsOneWidget);

    await tester.tap(find.text('Tandai Semua Dibaca'));
    await tester.pumpAndSettle();

    expect(alerts.unreadCount, 0);

    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('header-bell-badge')), findsNothing);

    dashboard.dispose();
  });

  testWidgets('grafik batang interaktif memakai data tujuh hari', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packageRepo = InMemoryPackageRepository();
    final categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    final usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);

    final now = DateTime.now();

    final id = await packageRepo.add(
      DataPackage(
        userId: 'u1',
        packageName: 'Paket Bulanan 30 GB',
        advertisedTotalQuotaBytes: 30000000000,
        startDate: dateOnly(now.subtract(const Duration(days: 5))),
        endDate: dateOnly(now.add(const Duration(days: 25))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _addDeviceUsage(usageRepo, id, now, 900000000);

    final usageService = _Usage(false);

    final dashboard = DashboardProvider(
      packageRepo,
      usageRepo,
      usageService,
      _Alert(),
      categoryRepo: categoryRepo,
      syncService: _appUsageSync(
        packageRepo,
        categoryRepo,
        usageRepo,
        usageService,
      ),
    );

    await tester.pumpWidget(_app(_FakeAuth(user), dashboard));
    await tester.pumpAndSettle();

    final chart = tester.widget<BarChart>(find.byType(BarChart));

    expect(chart.data.barGroups, hasLength(7));
    expect(chart.data.barTouchData.enabled, isTrue);
    expect(chart.data.barGroups.last.barRods.single.toY, 900000000);

    dashboard.dispose();
  });

  testWidgets('tombol Detail Aplikasi membuka rincian penggunaan aplikasi', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packageRepo = InMemoryPackageRepository();
    final categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    final usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);

    final now = DateTime.now();
    final start = dateOnly(now);

    final packageId = await packageRepo.add(
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

    await _addDeviceUsage(usageRepo, packageId, now, 900000000);

    // APP_USAGE yang sudah tersimpan dari sinkronisasi sebelumnya.
    final main = (await categoryRepo.getByPackage(packageId)).first;

    await usageRepo.upsertRecordWithAllocations(
      UsageRecord(
        packageId: packageId,
        recordScope: UsageRecordScope.appUsage,
        appUid: 101,
        appPackageName: 'com.instagram.android',
        appName: 'Instagram',
        networkType: NetworkType.mobile,
        periodStartAt: start,
        periodEndAt: start.add(const Duration(days: 1)),
        rxBytes: 3000000,
        txBytes: 0,
        source: UsageSource.android,
        sourceKey: 'android_app_test_instagram',
        recordedAt: now,
      ),
      (recordId) => [
        UsageAllocation(
          packageId: packageId,
          usageRecordId: recordId,
          quotaCategoryId: main.id,
          allocatedBytes: 3000000,
          allocationMethod: AllocationMethod.mainFallback,
          createdAt: now,
        ),
      ],
    );

    final usageService = _Usage(false);

    final dashboard = DashboardProvider(
      packageRepo,
      usageRepo,
      usageService,
      _Alert(),
      categoryRepo: categoryRepo,
      syncService: _appUsageSync(
        packageRepo,
        categoryRepo,
        usageRepo,
        usageService,
      ),
    );

    final breakdown = UsageBreakdownProvider(
      UsageBreakdownService(usageRepo),
      _appUsageSync(packageRepo, categoryRepo, usageRepo, usageService),
      usageService,
    );

    await tester.pumpWidget(
      _app(_FakeAuth(user), dashboard, breakdown: breakdown),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Detail Aplikasi'));
    await tester.pumpAndSettle();

    // Rincian nyata dari usage_records, bukan teks placeholder lama.
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('com.instagram.android'), findsOneWidget);
    expect(find.text('3,0 MB'), findsWidgets);
    expect(find.textContaining('setelah klasifikasi'), findsNothing);

    // Usage Access belum diberikan pada service palsu ini.
    expect(find.text('Izin Usage Access belum diberikan'), findsOneWidget);
    expect(find.text('Beri Izin Usage Access'), findsOneWidget);

    breakdown.dispose();
    dashboard.dispose();
  });
}
