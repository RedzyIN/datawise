import 'package:flutter_test/flutter_test.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';

DataPackage package({bool active = true, String uid = 'u1'}) => DataPackage(
  userId: uid, name: 'Paket', operator: 'Operator', totalBytes: 10000000000,
  initialUsedBytes: 0, startDate: DateTime(2026, 11, 1),
  endDate: DateTime(2026, 12, 1), price: null, isActive: active,
  createdAt: DateTime(2026, 11, 1), updatedAt: DateTime(2026, 11, 1),
);

void main() {
  group('InMemoryPackageRepository', () {
    test('hanya satu paket aktif per pengguna', () async {
      final repo = InMemoryPackageRepository();
      final first = await repo.add(package());
      final second = await repo.add(package());
      expect((await repo.getById(first))!.isActive, isFalse);
      expect((await repo.getById(second))!.isActive, isTrue);
      expect((await repo.getActive('u1'))!.id, second);
    });

    test('pengguna lain tidak terpengaruh saat paket diaktifkan', () async {
      final repo = InMemoryPackageRepository();
      final a = await repo.add(package());
      final b = await repo.add(package(uid: 'u2'));
      await repo.setActive('u1', a);
      expect((await repo.getById(b))!.isActive, isTrue);
    });
  });

  group('InMemoryUsageRepository', () {
    test('manual menggantikan auto pada tanggal yang sama', () async {
      final packages = InMemoryPackageRepository();
      final packageId = await packages.add(package());
      final usage = InMemoryUsageRepository(packages);
      final date = DateTime(2026, 11, 12);
      await usage.upsertRecord(packageId, date, 500, UsageSource.auto);
      await usage.upsertRecord(packageId, date, 300, UsageSource.manual);
      expect(await usage.getUsedBytesOn(packageId, date), 300);
      expect(await usage.getTotalUsedBytes(packageId), 300);
      expect((await usage.getRecords(packageId)).length, 2);
    });

    test('initial usage ditambahkan ke total pemakaian', () async {
      final packages = InMemoryPackageRepository();
      final id = await packages.add(package().copyWith(initialUsedBytes: 150));
      final usage = InMemoryUsageRepository(packages);
      await usage.upsertRecord(id, DateTime(2026, 11, 12), 250, UsageSource.auto);
      expect(await usage.getTotalUsedBytes(id), 400);
    });

    test('total alokasi tidak boleh melebihi pemakaian record', () async {
      final packages = InMemoryPackageRepository();
      final id = await packages.add(package());
      final usage = InMemoryUsageRepository(packages);
      await usage.upsertRecord(id, DateTime(2026, 11, 12), 100, UsageSource.auto);
      final record = (await usage.getRecords(id)).single;
      expect(
        () => usage.replaceAllocations(record.id!, [
          const UsageAllocation(usageRecordId: 1, categoryId: 1, usedBytes: 101),
        ]),
        throwsA(isA<AppException>()),
      );
    });

    test('menghapus paket ikut menghapus catatan dan alokasi', () async {
      final packages = InMemoryPackageRepository();
      final id = await packages.add(package());
      final usage = InMemoryUsageRepository(packages);
      await usage.upsertRecord(id, DateTime(2026, 11, 12), 100, UsageSource.auto);
      final record = (await usage.getRecords(id)).single;
      await usage.replaceAllocations(record.id!, [
        UsageAllocation(usageRecordId: record.id!, categoryId: 1, usedBytes: 50),
      ]);
      await packages.delete(id);
      expect(await usage.getRecords(id), isEmpty);
      expect(await usage.getAllocations(record.id!), isEmpty);
    });
  });
}
