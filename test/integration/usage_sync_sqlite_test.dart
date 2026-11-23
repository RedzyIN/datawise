// Pengujian integrasi nyata: Android (fake channel) → UsageSyncService →
// SQLite → DashboardProvider. Tidak memakai mock repository.
import 'package:datawise/core/constants.dart';
import 'package:datawise/core/db_helper.dart';
import 'package:datawise/features/dashboard/dashboard_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/sqlite/sqlite_repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeAndroidUsage implements UsageService {
  bool granted = true;
  int totalBytes = 0;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<void> openInternetSettings() async {}

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async {
    final now = DateTime.now();

    return UsageReading(
      status: granted ? UsageReadStatus.ok : UsageReadStatus.permissionDenied,
      totalBytes: granted ? totalBytes : 0,
      start: start,
      end: now,
      message: granted ? null : 'Izin akses penggunaan belum diberikan.',
    );
  }

  @override
  Future<AppUsageReading> readAppUsage(DateTime start, DateTime end) async {
    // Perangkat uji tidak menyediakan rincian per aplikasi.
    return AppUsageReading(
      status: UsageReadStatus.unsupported,
      buckets: const [],
      start: start,
      end: end,
      message: 'Rincian per aplikasi tidak tersedia pada pengujian ini.',
    );
  }

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    final now = DateTime.now();

    return readMobileUsage(dateOnly(now), now);
  }
}

class _NoopAlert implements AlertService {
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
  const userId = 'user-integrasi';
  const dbPath = 'datawise_usage_sync_integration_test.db';

  late DbHelper helper;
  late SqlitePackageRepository packages;
  late SqliteQuotaCategoryRepository categories;
  late SqliteUsageRepository usage;
  late SqliteDataLimitRepository limits;
  late _FakeAndroidUsage android;
  late DashboardProvider dashboard;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await databaseFactory.deleteDatabase(dbPath);

    helper = DbHelper.forTesting(dbPath);
    packages = SqlitePackageRepository(helper);
    categories = SqliteQuotaCategoryRepository(helper);
    usage = SqliteUsageRepository(helper);
    limits = SqliteDataLimitRepository(helper);
    android = _FakeAndroidUsage();

    final db = await helper.database;
    final now = DateTime.now().toIso8601String();

    await db.insert('users', {
      'id': userId,
      'display_name': 'Pengguna Integrasi',
      'email': 'integrasi@example.com',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    dashboard.dispose();
    await helper.close();
  });

  Future<String> createTenGbPackage({DateTime? start}) async {
    final now = DateTime.now();

    return packages.add(
      DataPackage(
        userId: userId,
        packageName: 'Paket 10 GB',
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10 * kBytesPerGB,
        startDate: dateOnly(start ?? now),
        endDate: dateOnly(now.add(const Duration(days: 30))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  DashboardProvider buildDashboard({bool granted = true, DbHelper? db}) {
    final h = db ?? helper;

    dashboard = DashboardProvider(
      SqlitePackageRepository(h),
      SqliteUsageRepository(h),
      android..granted = granted,
      _NoopAlert(),
      categoryRepo: SqliteQuotaCategoryRepository(h),
      dataLimitRepo: SqliteDataLimitRepository(h),
    );

    return dashboard;
  }

  test('paket, kategori, pemakaian perangkat, dan batas harian konsisten '
      'dari SQLite', () async {
    final packageId = await createTenGbPackage();

    final now = DateTime.now();
    final nightId = await categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: 'Kuota Malam',
        categoryType: QuotaCategoryType.night,
        capacityBytes: 2 * kBytesPerGB,
        isEnabled: true,
        createdAt: now,
      ),
    );
    final socialId = await categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: 'Kuota Sosial',
        categoryType: QuotaCategoryType.social,
        capacityBytes: 3 * kBytesPerGB,
        isEnabled: true,
        createdAt: now,
      ),
    );

    android.totalBytes = 100 * kBytesPerMB;

    final provider = buildDashboard(granted: true);
    await provider.refresh(userId);

    expect(provider.loadState, DashboardLoad.ready);
    expect(provider.package?.advertisedTotalQuotaBytes, 10 * kBytesPerGB);

    // 1. Pembacaan Android benar-benar tersimpan di SQLite.
    final records = await usage.getRecords(packageId);

    expect(records.length, 1);
    expect(records.single.recordScope, UsageRecordScope.deviceTotal);
    expect(records.single.source, UsageSource.android);
    expect(records.single.packageId, packageId);
    expect(records.single.totalBytes, 100 * kBytesPerMB);
    expect(
      records.single.sourceKey,
      'android_device_total_${packageId}_${dateToDb(dateOnly(now))}',
    );

    // 2. Dashboard membaca angka dari record, bukan langsung dari channel.
    expect(provider.totalUsedBytes, 100 * kBytesPerMB);
    expect(provider.unclassifiedBytes, 100 * kBytesPerMB);

    // 3. Kategori memakai kapasitas database dan tidak dibebani pemakaian
    //    agregat yang tidak bisa dipisahkan.
    expect(provider.categoryUsage.length, 3);

    final main = provider.categoryUsage.firstWhere(
      (item) => item.category.categoryType == QuotaCategoryType.main,
    );
    final night = provider.categoryUsage.firstWhere(
      (item) => item.category.id == nightId,
    );
    final social = provider.categoryUsage.firstWhere(
      (item) => item.category.id == socialId,
    );

    expect(main.capacityBytes, 5 * kBytesPerGB);
    expect(main.usedBytes, 0);
    expect(main.remainingBytes, 5 * kBytesPerGB);
    expect(night.capacityBytes, 2 * kBytesPerGB);
    expect(night.remainingBytes, 2 * kBytesPerGB);
    expect(social.capacityBytes, 3 * kBytesPerGB);
    expect(social.remainingBytes, 3 * kBytesPerGB);

    // 4. Batas harian 100 MB dengan pemakaian 100 MB = 100%.
    await limits.upsert(
      DataLimitSetting(
        packageId: packageId,
        dailyLimitBytes: 100 * kBytesPerMB,
        isEnabled: true,
        updatedAt: now,
      ),
    );

    await provider.refresh(userId);

    expect(provider.dataLimit.isConfigured, isTrue);
    expect(provider.dataLimit.percent, 100.0);
    expect(provider.dataLimit.isExceeded, isTrue);

    // 5. Refresh berulang tidak menduplikasi catatan.
    android.totalBytes = 120 * kBytesPerMB;
    await provider.refresh(userId);

    final afterRefresh = await usage.getRecords(packageId);

    expect(afterRefresh.length, 1);
    expect(afterRefresh.single.totalBytes, 120 * kBytesPerMB);
    expect(provider.totalUsedBytes, 120 * kBytesPerMB);
    expect(provider.dataLimit.percent, 120.0);

    // 6. Data tetap terbaca setelah repository dibuat ulang (restart aplikasi).
    final restarted = buildDashboard(granted: false);

    await restarted.refresh(userId);

    expect(restarted.loadState, DashboardLoad.ready);
    expect(restarted.totalUsedBytes, 120 * kBytesPerMB);
    expect(restarted.dataLimit.percent, 120.0);
    expect((await usage.getRecords(packageId)).length, 1);
  });

  test('pemakaian manual menggantikan agregat perangkat pada hari yang sama '
      'tanpa penghitungan ganda', () async {
    final packageId = await createTenGbPackage();

    android.totalBytes = 100 * kBytesPerMB;

    final provider = buildDashboard(granted: true);
    await provider.refresh(userId);

    expect(provider.totalUsedBytes, 100 * kBytesPerMB);

    final packageCategories = await categories.getByPackage(packageId);
    final mainId = packageCategories
        .firstWhere((item) => item.categoryType == QuotaCategoryType.main)
        .id!;

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
        rxBytes: 200 * kBytesPerMB,
        txBytes: 0,
        source: UsageSource.manual,
        sourceKey: 'manual_${packageId}_${dateToDb(start)}',
        recordedAt: now,
      ),
      (recordId) => [
        UsageAllocation(
          packageId: packageId,
          usageRecordId: recordId,
          quotaCategoryId: mainId,
          allocatedBytes: 200 * kBytesPerMB,
          allocationMethod: AllocationMethod.manualUser,
          createdAt: now,
        ),
      ],
    );

    await provider.refresh(userId);

    // Manual adalah deklarasi total pengguna untuk hari itu, jadi tidak
    // dijumlahkan dengan agregat perangkat.
    expect(provider.totalUsedBytes, 200 * kBytesPerMB);
    expect(provider.unclassifiedBytes, 0);

    final main = provider.categoryUsage.firstWhere(
      (item) => item.category.id == mainId,
    );

    expect(main.usedBytes, 200 * kBytesPerMB);
    expect(main.remainingBytes, 10 * kBytesPerGB - 200 * kBytesPerMB);

    final records = await usage.getRecords(packageId);

    expect(records.length, 2);
    expect(
      records
          .where((r) => r.recordScope == UsageRecordScope.deviceTotal)
          .length,
      1,
    );
    expect(
      records
          .where((r) => r.recordScope == UsageRecordScope.manualTotal)
          .length,
      1,
    );
  });
}
