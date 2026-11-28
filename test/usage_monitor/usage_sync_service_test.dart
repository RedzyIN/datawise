import 'package:datawise/core/constants.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:datawise/services/dashboard_data_limit_calculator.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:datawise/services/usage_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUsageService implements UsageService {
  UsageReadStatus status = UsageReadStatus.ok;
  int totalBytes = 0;
  int refreshCalls = 0;

  @override
  Future<bool> hasPermission() async => status == UsageReadStatus.ok;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<bool> openInternetSettings() async => true;

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async =>
      refreshToday(
        DataPackage(
          userId: 'u',
          packageName: 'p',
          advertisedTotalQuotaBytes: 1,
          startDate: start,
          endDate: end,
          status: PackageStatus.active,
          createdAt: start,
          updatedAt: start,
        ),
      );

  @override
  Future<AppUsageReading> readAppUsage(DateTime start, DateTime end) async {
    // Sinkronisasi total perangkat tidak memakai rincian per aplikasi.
    return AppUsageReading(
      status: UsageReadStatus.unsupported,
      buckets: const [],
      start: start,
      end: end,
      message: null,
    );
  }

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    refreshCalls++;

    final now = DateTime.now();

    return UsageReading(
      status: status,
      totalBytes: totalBytes,
      start: dateOnly(now),
      end: now,
      message: status == UsageReadStatus.ok ? null : 'izin belum diberikan',
    );
  }
}

void main() {
  late InMemoryPackageRepository packages;
  late InMemoryQuotaCategoryRepository categories;
  late InMemoryUsageRepository usage;
  late _FakeUsageService service;
  late UsageSyncService sync;

  setUp(() {
    packages = InMemoryPackageRepository();
    categories = InMemoryQuotaCategoryRepository(packages);
    usage = InMemoryUsageRepository(packages, categories);
    service = _FakeUsageService();
    sync = UsageSyncServiceImpl(service, usage);
  });

  Future<DataPackage> createPackage({
    String userId = 'user-1',
    String name = 'Paket 10 GB',
  }) async {
    final now = DateTime.now();
    final id = await packages.add(
      DataPackage(
        userId: userId,
        packageName: name,
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10 * kBytesPerGB,
        startDate: dateOnly(now.subtract(const Duration(days: 1))),
        endDate: dateOnly(now.add(const Duration(days: 30))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );

    return (await packages.getById(id))!;
  }

  test(
    'menyimpan pembacaan Android sebagai DEVICE_TOTAL milik paket aktif',
    () async {
      final package = await createPackage();
      service.totalBytes = 100 * kBytesPerMB;

      final result = await sync.syncToday(package);

      expect(result.status, UsageSyncStatus.saved);
      expect(result.record, isNotNull);

      final records = await usage.getRecords(package.id!);

      expect(records.length, 1);
      expect(records.single.packageId, package.id);
      expect(records.single.recordScope, UsageRecordScope.deviceTotal);
      expect(records.single.source, UsageSource.android);
      expect(records.single.networkType, NetworkType.mobile);
      expect(records.single.totalBytes, 100 * kBytesPerMB);
      expect(records.single.sourceKey, isNotNull);
      expect(records.single.periodStartAt, dateOnly(DateTime.now()));
    },
  );

  test(
    'pembacaan ulang hari yang sama memperbarui catatan yang sama',
    () async {
      final package = await createPackage();

      service.totalBytes = 50000000;
      await sync.syncToday(package);

      service.totalBytes = 75000000;
      await sync.syncToday(package);

      final records = await usage.getRecords(package.id!);

      expect(records.length, 1);
      expect(records.single.totalBytes, 75000000);
    },
  );

  test('izin ditolak tidak menyimpan catatan', () async {
    final package = await createPackage();
    service.status = UsageReadStatus.permissionDenied;

    final result = await sync.syncToday(package);

    expect(result.status, UsageSyncStatus.permissionDenied);
    expect(result.record, isNull);
    expect(await usage.getRecords(package.id!), isEmpty);
  });

  test('pembacaan gagal tidak menyimpan angka buatan', () async {
    final package = await createPackage();
    service.status = UsageReadStatus.error;
    service.totalBytes = 12345;

    final result = await sync.syncToday(package);

    expect(result.status, UsageSyncStatus.error);
    expect(await usage.getRecords(package.id!), isEmpty);
  });

  test('agregat perangkat tidak membuat alokasi kategori', () async {
    final package = await createPackage();
    service.totalBytes = 90000000;

    await sync.syncToday(package);

    final records = await usage.getRecords(package.id!);

    expect(await usage.getAllocations(records.single.id!), isEmpty);
    expect(await usage.getAllocationsByPackage(package.id!), isEmpty);

    final packageCategories = await categories.getByPackage(package.id!);

    expect(packageCategories.length, 1);
    expect(packageCategories.single.categoryType, QuotaCategoryType.main);
    expect(packageCategories.single.capacityBytes, 10 * kBytesPerGB);
  });

  test('catatan paket lain tidak tertimpa saat paket aktif berganti', () async {
    final first = await createPackage(name: 'Paket A');
    final second = await createPackage(name: 'Paket B');

    service.totalBytes = 10000000;
    await sync.syncToday(first);

    service.totalBytes = 20000000;
    await sync.syncToday(second);

    final firstRecords = await usage.getRecords(first.id!);
    final secondRecords = await usage.getRecords(second.id!);

    expect(firstRecords.single.totalBytes, 10000000);
    expect(secondRecords.single.totalBytes, 20000000);
  });

  test('paket tanpa ID tidak disimpan', () async {
    final now = DateTime.now();
    final package = DataPackage(
      userId: 'user-1',
      packageName: 'Paket Tanpa ID',
      advertisedTotalQuotaBytes: 10 * kBytesPerGB,
      startDate: dateOnly(now),
      endDate: dateOnly(now.add(const Duration(days: 30))),
      status: PackageStatus.active,
      createdAt: now,
      updatedAt: now,
    );

    final result = await sync.syncToday(package);

    expect(result.status, UsageSyncStatus.error);
    expect(service.refreshCalls, 0);
  });

  group('DashboardDataLimitCalculator', () {
    test('batas 100 MB dengan pemakaian 100 MB menghasilkan 100%', () {
      const limit = 100 * kBytesPerMB;
      final setting = DataLimitSetting(
        packageId: 'pkg',
        dailyLimitBytes: limit,
        isEnabled: true,
        updatedAt: DateTime.now(),
      );

      final status = DashboardDataLimitCalculator.evaluate(
        setting,
        100 * kBytesPerMB,
      );

      expect(status.isConfigured, isTrue);
      expect(status.percent, 100.0);
      expect(status.isExceeded, isTrue);
      expect(status.shouldWarn, isTrue);
    });

    test('pemakaian setengah batas menghasilkan 50% tanpa peringatan', () {
      final setting = DataLimitSetting(
        packageId: 'pkg',
        dailyLimitBytes: 100 * kBytesPerMB,
        isEnabled: true,
        updatedAt: DateTime.now(),
      );

      final status = DashboardDataLimitCalculator.evaluate(
        setting,
        50 * kBytesPerMB,
      );

      expect(status.percent, 50.0);
      expect(status.shouldWarn, isFalse);
      expect(status.isExceeded, isFalse);
    });

    test('tanpa batas atau batas nonaktif tidak menghasilkan persentase', () {
      expect(
        DashboardDataLimitCalculator.evaluate(null, 1000).isConfigured,
        isFalse,
      );

      final disabled = DataLimitSetting(
        packageId: 'pkg',
        dailyLimitBytes: 100 * kBytesPerMB,
        isEnabled: false,
        updatedAt: DateTime.now(),
      );

      final status = DashboardDataLimitCalculator.evaluate(disabled, 1000);

      expect(status.isConfigured, isFalse);
      expect(status.percent, 0);
    });
  });
}
