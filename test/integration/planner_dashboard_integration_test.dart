// Pengujian integrasi Data Planner melalui jalur produksi:
// SQLite → UsageRepository → DashboardProvider → PlannerService.
//
// Tanggal paket dibentuk relatif terhadap hari ini karena Dashboard memakai
// jam sistem, sedangkan perhitungan PlannerService sendiri diuji dengan
// tanggal tetap pada test/package/planner_service_test.dart.
import 'package:datawise/core/db_helper.dart';
import 'package:datawise/features/dashboard/dashboard_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/sqlite/sqlite_repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:datawise/services/app_usage_sync_service.dart';
import 'package:datawise/services/usage/usage_classification_service.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _userId = 'user-planner';
const _gb = 1000000000;
const _instagram = 'com.instagram.android';

DateTime _todayAt(int hour, int minute) =>
    dateOnly(DateTime.now()).add(Duration(hours: hour, minutes: minute));

AppUsageBucket _bucket({required int bytes}) => AppUsageBucket(
  uid: 101,
  packageName: _instagram,
  appName: 'Instagram',
  rxBytes: bytes,
  txBytes: 0,
  start: _todayAt(10, 0),
  end: _todayAt(10, 30),
);

class _FakeUsageService implements UsageService {
  int deviceBytes = 0;
  List<AppUsageBucket> buckets = const [];

  UsageReading _deviceReading(DateTime start, DateTime end) => UsageReading(
    status: UsageReadStatus.ok,
    totalBytes: deviceBytes,
    start: start,
    end: end,
    message: null,
  );

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<void> openInternetSettings() async {}

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async =>
      _deviceReading(start, end);

  @override
  Future<AppUsageReading> readAppUsage(DateTime start, DateTime end) async =>
      AppUsageReading(
        status: UsageReadStatus.ok,
        buckets: buckets,
        start: start,
        end: end,
        message: null,
      );

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    final now = DateTime.now();
    return _deviceReading(dateOnly(now), now);
  }
}

class _NoopAlertService implements AlertService {
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
  const dbPath = 'datawise_planner_dashboard_integration_test.db';

  late DbHelper helper;
  late SqlitePackageRepository packages;
  late SqliteQuotaCategoryRepository categories;
  late SqliteClassificationRuleRepository rules;
  late SqliteUsageRepository usage;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await databaseFactory.deleteDatabase(dbPath);

    helper = DbHelper.forTesting(dbPath);
    packages = SqlitePackageRepository(helper);
    categories = SqliteQuotaCategoryRepository(helper);
    rules = SqliteClassificationRuleRepository(helper);
    usage = SqliteUsageRepository(helper);

    final db = await helper.database;
    final now = DateTime.now().toIso8601String();

    await db.insert('users', {
      'id': _userId,
      'display_name': 'Pengguna Planner',
      'email': 'planner@example.com',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() => helper.close());

  Future<String> createPackage() {
    final now = DateTime.now();

    return packages.add(
      DataPackage(
        userId: _userId,
        packageName: 'Paket 10 GB',
        operatorName: 'Telkomsel',
        // End date today + 5 => 6 hari tersisa (inklusif).
        advertisedTotalQuotaBytes: 10 * _gb,
        startDate: dateOnly(now.subtract(const Duration(days: 4))),
        endDate: dateOnly(now.add(const Duration(days: 5))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  DashboardProvider buildDashboard(_FakeUsageService monitor) {
    final dashboard = DashboardProvider(
      packages,
      usage,
      monitor,
      _NoopAlertService(),
      categoryRepo: categories,
      syncService: AppUsageSyncService(
        monitor,
        usage,
        UsageClassificationService(
          ruleRepository: rules,
          categoryRepository: categories,
          usageRepository: usage,
        ),
      ),
    );

    addTearDown(dashboard.dispose);
    return dashboard;
  }

  test('Dashboard menghitung ulang target saat pemakaian bertambah', () async {
    final packageId = await createPackage();
    final monitor = _FakeUsageService()
      ..deviceBytes = 2 * _gb
      ..buckets = [_bucket(bytes: 1 * _gb)];

    final dashboard = buildDashboard(monitor);

    await dashboard.refresh(_userId);

    expect(dashboard.plan, isNotNull);
    expect(dashboard.plan!.status, PlannerStatus.normal);
    expect(dashboard.plan!.remainingDays, 6);
    expect(dashboard.plan!.usedBytes, 2 * _gb);
    expect(dashboard.totalUsedBytes, 2 * _gb);
    expect(dashboard.plan!.remainingBytes, 8 * _gb);
    expect(dashboard.plan!.dailyTargetBytes, closeTo(8 * _gb / 6, 1));
    expect(
      dashboard.plan!.weeklyTargetBytes,
      closeTo(dashboard.plan!.dailyTargetBytes! * 6, 1),
    );

    final firstDaily = dashboard.plan!.dailyTargetBytes!;
    final firstWeekly = dashboard.plan!.weeklyTargetBytes!;

    // Pemakaian perangkat bertambah; APP_USAGE yang sama tidak dijumlahkan.
    monitor.deviceBytes = 4 * _gb;

    await dashboard.refresh(_userId);

    expect(dashboard.plan!.usedBytes, 4 * _gb);
    expect(dashboard.totalUsedBytes, 4 * _gb);
    expect(dashboard.plan!.remainingBytes, 6 * _gb);
    expect(dashboard.plan!.dailyTargetBytes, closeTo(6 * _gb / 6, 1));
    expect(dashboard.plan!.dailyTargetBytes!, lessThan(firstDaily));
    expect(dashboard.plan!.weeklyTargetBytes!, lessThan(firstWeekly));
    expect(
      dashboard.plan!.weeklyTargetBytes,
      closeTo(dashboard.plan!.dailyTargetBytes! * 6, 1),
    );

    // Catatan tersimpan tetap satu DEVICE_TOTAL dan satu APP_USAGE.
    final records = await usage.getRecords(packageId);

    expect(
      records.where(
        (record) => record.recordScope == UsageRecordScope.deviceTotal,
      ),
      hasLength(1),
    );
    expect(
      records.where(
        (record) => record.recordScope == UsageRecordScope.appUsage,
      ),
      hasLength(1),
    );
  });

  test('target depleted tidak negatif saat pemakaian melewati kuota', () async {
    await createPackage();

    final monitor = _FakeUsageService()..deviceBytes = 12 * _gb;
    final dashboard = buildDashboard(monitor);

    await dashboard.refresh(_userId);

    expect(dashboard.plan!.status, PlannerStatus.depleted);
    expect(dashboard.plan!.remainingBytes, 0);
    expect(dashboard.plan!.usagePercent, closeTo(120, 0.001));
    expect(dashboard.plan!.dailyTargetBytes, 0);
    expect(dashboard.plan!.weeklyTargetBytes, 0);
    expect(dashboard.plan!.todayPercentOfTarget, isNull);
  });

  test(
    'peralihan Android ke manual tidak menghitung ganda dan target naik',
    () async {
      final packageId = await createPackage();

      final monitor = _FakeUsageService()
        ..deviceBytes = 4 * _gb
        ..buckets = [_bucket(bytes: 1 * _gb)];

      final dashboard = buildDashboard(monitor);

      await dashboard.refresh(_userId);

      expect(dashboard.plan!.usedBytes, 4 * _gb);
      expect(dashboard.plan!.remainingDays, 6);

      final androidDailyTarget = dashboard.plan!.dailyTargetBytes!;

      final main = (await categories.getByPackage(packageId)).firstWhere(
        (category) => category.categoryType == QuotaCategoryType.main,
      );
      final now = DateTime.now();
      final start = dateOnly(now);

      await usage.upsertRecordWithAllocations(
        UsageRecord(
          packageId: packageId,
          recordScope: UsageRecordScope.manualTotal,
          networkType: NetworkType.mobile,
          periodStartAt: start,
          periodEndAt: now.isAfter(start)
              ? now
              : start.add(const Duration(seconds: 1)),
          rxBytes: 3 * _gb,
          txBytes: 0,
          source: UsageSource.manual,
          sourceKey: 'manual_${packageId}_${start.millisecondsSinceEpoch}',
          recordedAt: now,
        ),
        (usageRecordId) => [
          UsageAllocation(
            packageId: packageId,
            usageRecordId: usageRecordId,
            quotaCategoryId: main.id,
            allocatedBytes: 3 * _gb,
            allocationMethod: AllocationMethod.manualUser,
            createdAt: now,
          ),
        ],
      );

      await dashboard.refresh(_userId);

      // MANUAL_TOTAL menggantikan DEVICE_TOTAL dan APP_USAGE hari itu.
      expect(dashboard.plan!.usedBytes, 3 * _gb);
      expect(dashboard.totalUsedBytes, 3 * _gb);
      expect(dashboard.plan!.remainingBytes, 7 * _gb);
      expect(dashboard.plan!.remainingDays, 6);
      expect(dashboard.plan!.dailyTargetBytes, closeTo(7 * _gb / 6, 1));
      expect(
        dashboard.plan!.dailyTargetBytes!,
        greaterThan(androidDailyTarget),
      );
      expect(dashboard.plan!.status, PlannerStatus.normal);
    },
  );
}
