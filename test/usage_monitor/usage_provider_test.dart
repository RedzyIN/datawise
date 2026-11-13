import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/features/usage_monitor/usage_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:datawise/services/usage_service.dart';

// Fake service untuk menggantikan komunikasi dengan Android.
class FakeUsageService implements UsageService {
  bool permissionGranted = false;
  int refreshCallCount = 0;

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

    return UsageReading(
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
  late InMemoryUsageRepository usageRepo;
  late UsageProvider provider;

  setUp(() {
    fakeService = FakeUsageService();
    packageRepo = InMemoryPackageRepository();
    usageRepo = InMemoryUsageRepository(packageRepo);

    provider = UsageProvider(fakeService, usageRepo, packageRepo);
  });

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
    test('berhasil membaca penggunaan data', () async {
      final packageId = await packageRepo.add(
        DataPackage(
          userId: 'user-1',
          name: 'Paket Internet',
          operator: 'Telkomsel',
          totalBytes: 10 * 1024 * 1024,
          initialUsedBytes: 0,
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 30)),
          price: 50000,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final package = await packageRepo.getById(packageId);

      await provider.refresh(package!);

      expect(fakeService.refreshCallCount, 1);
      expect(provider.lastReading, isNotNull);
      expect(provider.lastReading!.totalBytes, 1000);
      expect(provider.lastRefresh, isNotNull);
      expect(provider.isLoading, false);
      expect(provider.errorMessage, isNull);
    });
  });
  group('UsageProvider - Manual Usage', () {
    test('berhasil menyimpan penggunaan data manual', () async {
      final packageId = await packageRepo.add(
        DataPackage(
          userId: 'user-1',
          name: 'Paket Internet',
          operator: 'Telkomsel',
          totalBytes: 10 * 1024 * 1024,
          initialUsedBytes: 0,
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 30)),
          price: 50000,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final package = await packageRepo.getById(packageId);

      await provider.saveManualToday(package!, 5000);

      final records = await usageRepo.getRecords(packageId);

      expect(records.length, 1);
      expect(records.first.usedBytes, 5000);
      expect(records.first.source, UsageSource.manual);
      expect(provider.errorMessage, isNull);
    });
    test('berhasil menghapus penggunaan data manual', () async {
      final packageId = await packageRepo.add(
        DataPackage(
          userId: 'user-1',
          name: 'Paket Internet',
          operator: 'Telkomsel',
          totalBytes: 10 * 1024 * 1024,
          initialUsedBytes: 0,
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 30)),
          price: 50000,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final package = await packageRepo.getById(packageId);

      // Simpan data manual terlebih dahulu.
      await provider.saveManualToday(package!, 5000);

      // Hapus data manual hari ini.
      await provider.deleteManualToday(package);

      final records = await usageRepo.getRecords(packageId);

      expect(records, isEmpty);
      expect(provider.errorMessage, isNull);
    });
    test('menolak penggunaan data dengan nilai negatif', () async {
      final packageId = await packageRepo.add(
        DataPackage(
          userId: 'user-1',
          name: 'Paket Internet',
          operator: 'Telkomsel',
          totalBytes: 10 * 1024 * 1024,
          initialUsedBytes: 0,
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 30)),
          price: 50000,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final package = await packageRepo.getById(packageId);

      await provider.saveManualToday(package!, -5000);

      final records = await usageRepo.getRecords(packageId);

      expect(records, isEmpty);
      expect(provider.errorMessage, isNotNull);
    });
  });
  group('UsageProvider - Initial Usage', () {
    test('berhasil mengubah penggunaan awal paket', () async {
      final packageId = await packageRepo.add(
        DataPackage(
          userId: 'user-1',
          name: 'Paket Internet',
          operator: 'Telkomsel',
          totalBytes: 10 * 1024 * 1024,
          initialUsedBytes: 0,
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 30)),
          price: 50000,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final package = await packageRepo.getById(packageId);

      await provider.setInitialUsed(package!, 2000);

      final updatedPackage = await packageRepo.getById(packageId);

      expect(updatedPackage!.initialUsedBytes, 2000);
      expect(provider.errorMessage, isNull);
    });
  });
}
