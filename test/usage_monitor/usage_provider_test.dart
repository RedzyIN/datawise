import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/features/usage_monitor/usage_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:datawise/services/usage_service.dart';

// Fake service untuk menggantikan komunikasi dengan Android.
class FakeUsageService implements UsageService {
  bool permissionGranted = false;
  int refreshCallCount = 0;

  UsageReading? nextReading;

  @override
  Future<bool> hasPermission() async {
    return permissionGranted;
  }

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<void> openInternetSettings() async {}

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async {
    return UsageReading(
      status: UsageReadStatus.ok,
      totalBytes: 1000,
      start: start,
      end: end,
      message: null,
    );
  }

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    refreshCallCount++;

    final now = DateTime.now();

    return nextReading ??
        UsageReading(
          status: UsageReadStatus.ok,
          totalBytes: 1000,
          start: dateOnly(now),
          end: now,
          message: null,
        );
  }
}

void main() {
  late FakeUsageService fakeService;

  late InMemoryPackageRepository packageRepo;
  late InMemoryQuotaCategoryRepository categoryRepo;
  late InMemoryUsageRepository usageRepo;

  late UsageProvider provider;

  setUp(() {
    fakeService = FakeUsageService();

    packageRepo = InMemoryPackageRepository();

    // Repository kategori harus dibuat sebelum paket ditambahkan.
    categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);

    // Repository penggunaan membutuhkan repository kategori
    // untuk memvalidasi UsageAllocation.
    usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);

    provider = UsageProvider(fakeService, usageRepo, categoryRepo);
  });

  tearDown(() {
    provider.dispose();
  });

  Future<DataPackage> createActivePackage() async {
    final now = DateTime.now();

    final package = DataPackage(
      userId: 'user-1',
      packageName: 'Paket Internet',
      operatorName: 'Telkomsel',
      advertisedTotalQuotaBytes: 10 * 1024 * 1024,
      startDate: dateOnly(now),
      endDate: dateOnly(now.add(const Duration(days: 30))),
      status: PackageStatus.active,
      createdAt: now,
      updatedAt: now,
    );

    final packageId = await packageRepo.add(package);

    return (await packageRepo.getById(packageId))!;
  }

  group('UsageProvider - Check Permission', () {
    test('izin diberikan, hasPermission bernilai true', () async {
      fakeService.permissionGranted = true;

      await provider.checkPermission();

      expect(provider.hasPermission, true);
      expect(provider.errorMessage, isNull);
    });

    test('izin ditolak, hasPermission bernilai false', () async {
      fakeService.permissionGranted = false;

      await provider.checkPermission();

      expect(provider.hasPermission, false);
      expect(provider.errorMessage, isNotNull);
    });
  });

  group('UsageProvider - Refresh', () {
    test('berhasil membaca penggunaan data perangkat', () async {
      final package = await createActivePackage();

      await provider.refresh(package);

      expect(fakeService.refreshCallCount, 1);
      expect(provider.lastReading, isNotNull);
      expect(provider.lastReading!.totalBytes, 1000);
      expect(provider.lastReading!.status, UsageReadStatus.ok);
      expect(provider.lastRefresh, isNotNull);
      expect(provider.isLoading, false);
      expect(provider.errorMessage, isNull);
    });

    test('hasil pembacaan agregat perangkat disimpan sebagai DEVICE_TOTAL tanpa alokasi', () async {
      final package = await createActivePackage();

      await provider.refresh(package);

      final records = await usageRepo.getRecords(package.id!);

      expect(records.length, 1);
      expect(records.single.recordScope, UsageRecordScope.deviceTotal);
      expect(records.single.source, UsageSource.android);
      expect(records.single.packageId, package.id);
      expect(records.single.totalBytes, 1000);

      // Agregat perangkat tidak boleh dialokasikan ke kategori mana pun.
      expect(await usageRepo.getAllocations(records.single.id!), isEmpty);
      expect(provider.lastReading!.totalBytes, 1000);
    });

    test('pembacaan berulang tidak membuat catatan ganda', () async {
      final package = await createActivePackage();

      await provider.refresh(package);
      await provider.refresh(package);

      final records = await usageRepo.getRecords(package.id!);

      expect(records.length, 1);
      expect(records.single.totalBytes, 1000);
    });

    test('gagal membaca penggunaan data', () async {
      final package = await createActivePackage();

      fakeService.nextReading = UsageReading(
        status: UsageReadStatus.permissionDenied,
        totalBytes: 0,
        start: dateOnly(DateTime.now()),
        end: DateTime.now(),
        message: 'Izin Usage Access belum diberikan.',
      );

      await provider.refresh(package);

      expect(provider.lastReading, isNotNull);
      expect(provider.lastReading!.status, UsageReadStatus.permissionDenied);
      expect(provider.errorMessage, isNotNull);
      expect(provider.isLoading, false);
    });
  });

  group('UsageProvider - Manual Usage', () {
    test('berhasil menyimpan penggunaan manual beserta alokasinya', () async {
      final package = await createActivePackage();

      await provider.saveManualToday(package, 5000);

      final records = await usageRepo.getRecords(package.id!);

      expect(records.length, 1);

      final record = records.single;

      expect(record.totalBytes, 5000);
      expect(record.rxBytes, 5000);
      expect(record.txBytes, 0);
      expect(record.source, UsageSource.manual);
      expect(record.recordScope, UsageRecordScope.manualTotal);
      expect(record.networkType, NetworkType.mobile);

      final allocations = await usageRepo.getAllocations(record.id!);

      expect(allocations.length, 1);
      expect(allocations.single.allocatedBytes, 5000);
      expect(allocations.single.allocationMethod, AllocationMethod.manualUser);

      final categories = await categoryRepo.getByPackage(package.id!);

      final mainCategory = categories.firstWhere(
        (category) => category.categoryType == QuotaCategoryType.main,
      );

      expect(allocations.single.quotaCategoryId, mainCategory.id);

      expect(provider.errorMessage, isNull);
    });

    test('menyimpan ulang penggunaan manual hari ini memperbarui catatan yang sama', () async {
      final package = await createActivePackage();

      await provider.saveManualToday(package, 5000);
      await provider.saveManualToday(package, 9000);

      final records = await usageRepo.getRecords(package.id!);

      expect(records.length, 1);
      expect(records.single.totalBytes, 9000);

      final allocations = await usageRepo.getAllocations(records.single.id!);

      expect(allocations.length, 1);
      expect(allocations.single.allocatedBytes, 9000);

      expect(provider.errorMessage, isNull);
    });

    test('berhasil menghapus penggunaan manual hari ini', () async {
      final package = await createActivePackage();

      await provider.saveManualToday(package, 5000);

      final recordsBeforeDelete = await usageRepo.getRecords(package.id!);

      expect(recordsBeforeDelete.length, 1);

      await provider.deleteManualToday(package);

      final recordsAfterDelete = await usageRepo.getRecords(package.id!);

      expect(recordsAfterDelete, isEmpty);

      final allocations = await usageRepo.getAllocationsByPackage(package.id!);

      expect(allocations, isEmpty);
      expect(provider.errorMessage, isNull);
    });

    test('menolak penggunaan data dengan nilai negatif', () async {
      final package = await createActivePackage();

      await provider.saveManualToday(package, -5000);

      final records = await usageRepo.getRecords(package.id!);

      expect(records, isEmpty);
      expect(provider.errorMessage, isNotNull);
    });

    test('menolak paket yang belum memiliki ID', () async {
      final now = DateTime.now();

      final package = DataPackage(
        userId: 'user-1',
        packageName: 'Paket Tanpa ID',
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10 * 1024 * 1024,
        startDate: dateOnly(now),
        endDate: dateOnly(now.add(const Duration(days: 30))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      );

      await provider.saveManualToday(package, 5000);

      expect(provider.errorMessage, isNotNull);
    });
  });
}
