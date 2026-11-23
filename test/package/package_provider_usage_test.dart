import 'package:datawise/core/constants.dart';
import 'package:datawise/features/package/package_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryPackageRepository packages;
  late InMemoryQuotaCategoryRepository categories;
  late InMemoryUsageRepository usage;

  DataPackage pkg() {
    final now = DateTime.now();

    return DataPackage(
      userId: 'u1',
      packageName: 'Paket 10 GB',
      operatorName: 'Telkomsel',
      advertisedTotalQuotaBytes: 10 * kBytesPerGB,
      startDate: dateOnly(now.subtract(const Duration(days: 2))),
      endDate: dateOnly(now.add(const Duration(days: 20))),
      status: PackageStatus.active,
      createdAt: now,
      updatedAt: now,
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

  setUp(() {
    packages = InMemoryPackageRepository();
    categories = InMemoryQuotaCategoryRepository(packages);
    usage = InMemoryUsageRepository(packages, categories);
  });

  test('sisa kuota memakai pemakaian efektif tanpa menghitung ganda', () async {
    final id = await packages.add(pkg());
    final main = (await categories.getByPackage(id)).single;
    final now = DateTime.now();
    final start = dateOnly(now);

    await usage.upsertRecordWithAllocations(
      UsageRecord(
        packageId: id,
        recordScope: UsageRecordScope.manualTotal,
        networkType: NetworkType.mobile,
        periodStartAt: start,
        periodEndAt: start.add(const Duration(hours: 1)),
        rxBytes: 500000000,
        txBytes: 0,
        source: UsageSource.manual,
        sourceKey: 'manual-1',
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

    // DEVICE_TOTAL pada tanggal yang sama tidak boleh ditambahkan lagi.
    await addDeviceRecord(id, now, 900000000);

    final provider = PackageProvider(packages, usageRepo: usage);

    await provider.load('u1');

    expect(provider.usedBytesFor(id), 500000000);

    final package = provider.packages.single;

    expect(provider.remainingBytesFor(package), 10 * kBytesPerGB - 500000000);

    // Pemakaian perangkat pada tanggal lain tetap dihitung.
    await addDeviceRecord(id, now.subtract(const Duration(days: 1)), 100000000);
    await provider.load('u1');

    expect(provider.usedBytesFor(id), 600000000);
  });

  test(
    'paket tanpa catatan pemakaian memiliki sisa sama dengan total',
    () async {
      await packages.add(pkg());

      final provider = PackageProvider(packages, usageRepo: usage);
      await provider.load('u1');

      final package = provider.packages.single;

      expect(provider.usedBytesFor(package.id), 0);
      expect(provider.remainingBytesFor(package), 10 * kBytesPerGB);
    },
  );
}
