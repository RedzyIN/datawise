import 'package:datawise/features/dashboard/dashboard_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:datawise/services/app_usage_sync_service.dart';
import 'package:datawise/services/usage/usage_classification_service.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUsageService implements UsageService {
  _FakeUsageService(this.granted, {this.totalBytes = 0});

  final bool granted;
  final int totalBytes;

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
      totalBytes: totalBytes,
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
  late InMemoryQuotaCategoryRepository categories;
  late InMemoryClassificationRuleRepository rules;
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

  AppUsageSyncService appUsageSync(UsageService service) {
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

  DashboardProvider build({
    required bool granted,
    int totalBytes = 0,
    DashboardPlanner? planner,
  }) {
    final service = _FakeUsageService(granted, totalBytes: totalBytes);

    return DashboardProvider(
      packages,
      usage,
      service,
      _FakeAlertService(),
      categoryRepo: categories,
      syncService: appUsageSync(service),
      planner: planner,
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

  DashboardProvider buildWithPlanner({required bool granted}) {
    final service = _FakeUsageService(granted);

    return DashboardProvider(
      packages,
      usage,
      service,
      _FakeAlertService(),
      categoryRepo: categories,
      syncService: appUsageSync(service),
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
              usedBytes: totalUsedBytes,
              remainingBytes:
                  package.advertisedTotalQuotaBytes - totalUsedBytes,
              remainingDays: 10,
              dailyTargetBytes: 1000000000,
              weeklyTargetBytes: 7000000000,
              todayUsedBytes: todayUsedBytes,
              usagePercent: 0,
              todayPercentOfTarget: 0,
            );
          },
    );
  }

  setUp(() {
    packages = InMemoryPackageRepository();
    categories = InMemoryQuotaCategoryRepository(packages);
    rules = InMemoryClassificationRuleRepository(packages, categories);
    usage = InMemoryUsageRepository(packages, categories, rules);
  });

  test('memuat kategori paket dan sisa kategori dari repository', () async {
    final id = await packages.add(pkg('uid_1'));
    final main = (await categories.getByPackage(id)).single;
    final now = DateTime.now();

    await usage.upsertRecordWithAllocations(
      UsageRecord(
        packageId: id,
        recordScope: UsageRecordScope.manualTotal,
        networkType: NetworkType.mobile,
        periodStartAt: dateOnly(now),
        periodEndAt: now,
        rxBytes: 500000000,
        txBytes: 0,
        source: UsageSource.manual,
        recordedAt: now,
      ),
      (usageRecordId) => [
        UsageAllocation(
          packageId: id,
          usageRecordId: usageRecordId,
          quotaCategoryId: main.id,
          allocatedBytes: 500000000,
          allocationMethod: AllocationMethod.manualUser,
          createdAt: now,
        ),
      ],
    );

    final dashboard = build(granted: false);

    await dashboard.refresh('uid_1');

    expect(dashboard.categoryUsage, hasLength(1));

    final mainUsage = dashboard.categoryUsage.single;

    expect(mainUsage.category.categoryName, 'Kuota Utama');
    expect(mainUsage.category.categoryType, QuotaCategoryType.main);
    expect(mainUsage.usedBytes, 500000000);
    expect(mainUsage.remainingBytes, 25 * kBytesPerGBForTest - 500000000);

    expect(dashboard.unclassifiedBytes, 0);

    dashboard.dispose();
  });

  test(
    'pemakaian perangkat tanpa alokasi dihitung belum masuk kategori',
    () async {
      final id = await packages.add(pkg('uid_1'));

      await addDeviceRecord(id, DateTime.now(), 500000000);

      final dashboard = build(granted: false);

      await dashboard.refresh('uid_1');

      expect(dashboard.categoryUsage, hasLength(1));
      expect(dashboard.categoryUsage.single.usedBytes, 0);
      expect(dashboard.unclassifiedBytes, 500000000);

      dashboard.dispose();
    },
  );

  test('tanpa paket aktif menghasilkan noPackage', () async {
    final dashboard = build(granted: false);

    await dashboard.refresh('uid_1');

    expect(dashboard.loadState, DashboardLoad.noPackage);
    expect(dashboard.package, isNull);

    dashboard.dispose();
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

    dashboard.dispose();
  });

  test('data akun lain tidak ditampilkan', () async {
    await packages.add(pkg('uid_A'));

    final dashboard = build(granted: false);

    await dashboard.refresh('uid_B');

    expect(dashboard.loadState, DashboardLoad.noPackage);
    expect(dashboard.package, isNull);

    dashboard.dispose();
  });

  test('DEVICE_TOTAL dipilih tanpa menjumlahkan APP_USAGE', () async {
    final id = await packages.add(pkg('uid_1'));
    final today = dateOnly(DateTime.now());

    await addDeviceRecord(id, today, 500000000);

    final dashboard = build(granted: false);

    await dashboard.refresh('uid_1');

    expect(dashboard.dailyUsage[today], 500000000);
    expect(dashboard.totalUsedBytes, 500000000);

    dashboard.dispose();
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

    dashboard.dispose();
  });

  test('planner yang gagal membuat Dashboard tetap ready', () async {
    await packages.add(pkg('uid_1'));

    final dashboard = build(
      granted: true,
      planner: ({
        required DataPackage package,
        required int totalUsedBytes,
        required int todayUsedBytes,
        required DateTime today,
      }) => throw UnimplementedError('planner gagal'),
    );

    await dashboard.refresh('uid_1');

    expect(dashboard.loadState, DashboardLoad.ready);
    expect(dashboard.package, isNotNull);
    expect(dashboard.plan, isNull);
    expect(dashboard.planUnavailable, isTrue);

    dashboard.dispose();
  });

  test(
    'statistik perangkat hari ini tersimpan dan digunakan Dashboard',
    () async {
      await packages.add(pkg('uid_1'));

      final today = dateOnly(DateTime.now());

      final dashboard = build(granted: true, totalBytes: 700000000);

      await dashboard.refresh('uid_1');

      expect(dashboard.dailyUsage[today], 700000000);
      expect(dashboard.totalUsedBytes, 700000000);
      expect(dashboard.categoryUsage.single.usedBytes, 0);
      expect(dashboard.unclassifiedBytes, 700000000);

      dashboard.dispose();
    },
  );

  test('catatan manual hari ini menang atas statistik perangkat', () async {
    final id = await packages.add(pkg('uid_1'));
    final main = (await categories.getByPackage(id)).single;
    final now = DateTime.now();

    await usage.upsertRecordWithAllocations(
      UsageRecord(
        packageId: id,
        recordScope: UsageRecordScope.manualTotal,
        networkType: NetworkType.mobile,
        periodStartAt: dateOnly(now),
        periodEndAt: now,
        rxBytes: 300000000,
        txBytes: 0,
        source: UsageSource.manual,
        recordedAt: now,
      ),
      (usageRecordId) => [
        UsageAllocation(
          packageId: id,
          usageRecordId: usageRecordId,
          quotaCategoryId: main.id,
          allocatedBytes: 300000000,
          allocationMethod: AllocationMethod.manualUser,
          createdAt: now,
        ),
      ],
    );

    final dashboard = build(granted: true, totalBytes: 700000000);

    await dashboard.refresh('uid_1');

    expect(dashboard.dailyUsage[dateOnly(now)], 300000000);
    expect(dashboard.totalUsedBytes, 300000000);
    expect(dashboard.unclassifiedBytes, 0);

    dashboard.dispose();
  });

  test('planner yang tersedia mengisi target harian dan mingguan', () async {
    await packages.add(pkg('uid_1'));

    final dashboard = buildWithPlanner(granted: true);

    await dashboard.refresh('uid_1');

    expect(dashboard.planUnavailable, isFalse);
    expect(dashboard.plan, isNotNull);
    expect(dashboard.plan?.dailyTargetBytes, 1000000000);
    expect(dashboard.plan?.weeklyTargetBytes, 7000000000);

    dashboard.dispose();
  });

  test('izin belum diberikan tidak menghasilkan waktu pembaruan', () async {
    await packages.add(pkg('uid_1'));

    final dashboard = build(granted: false);

    await dashboard.refresh('uid_1');

    expect(dashboard.hasPermission, isFalse);
    expect(dashboard.lastUpdatedAt, isNull);

    dashboard.dispose();
  });

  test(
    'planner bawaan menghitung target dari sisa kuota dan sisa hari',
    () async {
      final id = await packages.add(pkg('uid_1'));

      await addDeviceRecord(id, DateTime.now(), 1000000000);

      final dashboard = build(granted: false);

      await dashboard.refresh('uid_1');

      expect(dashboard.planUnavailable, isFalse);
      expect(dashboard.plan, isNotNull);
      expect(dashboard.plan!.dailyTargetBytes, greaterThan(0));
      expect(dashboard.plan!.weeklyTargetBytes, greaterThan(0));
      expect(dashboard.plan!.todayPercentOfTarget, isNotNull);
      expect(dashboard.plan!.usedBytes, 1000000000);

      dashboard.dispose();
    },
  );

  test(
    'alokasi UNCLASSIFIED tidak dihitung sebagai pemakaian kategori',
    () async {
      final id = await packages.add(pkg('uid_1'));
      final now = DateTime.now();
      final start = dateOnly(now);

      await usage.upsertRecordWithAllocations(
        UsageRecord(
          packageId: id,
          recordScope: UsageRecordScope.appUsage,
          appUid: 10001,
          appPackageName: 'com.example.app',
          appName: 'Contoh',
          networkType: NetworkType.mobile,
          periodStartAt: start,
          periodEndAt: start.add(const Duration(hours: 1)),
          rxBytes: 300000000,
          txBytes: 0,
          source: UsageSource.android,
          recordedAt: now,
        ),
        (usageRecordId) => [
          UsageAllocation(
            packageId: id,
            usageRecordId: usageRecordId,
            allocatedBytes: 300000000,
            allocationMethod: AllocationMethod.unclassified,
            createdAt: now,
          ),
        ],
      );

      final dashboard = build(granted: false);

      await dashboard.refresh('uid_1');

      expect(dashboard.categoryUsage.single.usedBytes, 0);
      expect(dashboard.unclassifiedBytes, 300000000);
      expect(dashboard.totalUsedBytes, 300000000);

      dashboard.dispose();
    },
  );
}

const int kBytesPerGBForTest = 1000000000;
