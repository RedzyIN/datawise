import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';

DataPackage createPackage({
  PackageStatus status = PackageStatus.active,
  String userId = 'u1',
  DateTime? endDate,
}) {
  final now = DateTime(2026, 11, 1);

  return DataPackage(
    userId: userId,
    packageName: 'Paket',
    operatorName: 'Operator',
    advertisedTotalQuotaBytes: 10000000000,
    startDate: DateTime(2026, 11, 1),
    endDate: endDate ?? DateTime(2026, 12, 1),
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

UsageRecord createUsageRecord({
  required String packageId,
  UsageSource source = UsageSource.android,
  String? sourceKey,
  UsageRecordScope scope = UsageRecordScope.deviceTotal,
  int rxBytes = 60,
  int txBytes = 40,
}) {
  final start = DateTime(2026, 11, 12);
  final end = DateTime(2026, 11, 13);

  return UsageRecord(
    packageId: packageId,
    recordScope: scope,
    appPackageName: scope == UsageRecordScope.appUsage ? 'com.example.app' : null,
    networkType: NetworkType.mobile,
    periodStartAt: start,
    periodEndAt: end,
    rxBytes: rxBytes,
    txBytes: txBytes,
    source: source,
    sourceKey: sourceKey,
    recordedAt: end,
  );
}

void main() {
  group('InMemoryPackageRepository', () {
    test('hanya satu paket aktif per pengguna', () async {
      final repo = InMemoryPackageRepository();

      final first = await repo.add(createPackage());
      final second = await repo.add(createPackage());

      expect((await repo.getById(first))!.status, PackageStatus.inactive);
      expect((await repo.getById(second))!.status, PackageStatus.active);
      expect((await repo.getActive('u1'))!.id, second);
    });

    test('pengguna lain tidak terpengaruh saat paket diaktifkan', () async {
      final repo = InMemoryPackageRepository();

      final first = await repo.add(createPackage());
      final second = await repo.add(createPackage(userId: 'u2'));

      await repo.setActive('u1', first);

      expect((await repo.getById(second))!.status, PackageStatus.active);
    });

    test('menolak aktivasi paket expired, archived, dan kedaluwarsa', () async {
      final repo = InMemoryPackageRepository();

      final expiredId = await repo.add(
        createPackage(status: PackageStatus.expired),
      );

      final archivedId = await repo.add(
        createPackage(status: PackageStatus.archived),
      );

      final pastEndDateId = await repo.add(
        createPackage(
          status: PackageStatus.inactive,
          endDate: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      await expectLater(
        repo.setActive('u1', expiredId),
        throwsA(isA<AppException>()),
      );

      await expectLater(
        repo.setActive('u1', archivedId),
        throwsA(isA<AppException>()),
      );

      await expectLater(
        repo.setActive('u1', pastEndDateId),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('InMemoryClassificationRuleRepository', () {
    test('classification rules order honors priority and specificity', () async {
      final packages = InMemoryPackageRepository();
      final categories = InMemoryQuotaCategoryRepository(packages);
      final packageId = await packages.add(createPackage());
      final main = (await categories.getByPackage(packageId)).single;
      final rules = InMemoryClassificationRuleRepository(packages, categories);
      final now = DateTime(2026, 11, 15);

      await rules.add(ClassificationRule(
        id: 'rule-general',
        quotaCategoryId: main.id!,
        ruleName: 'Semua aplikasi',
        priority: 100,
        isEnabled: true,
        createdAt: now,
      ));
      await rules.add(ClassificationRule(
        id: 'rule-specific',
        quotaCategoryId: main.id!,
        ruleName: 'Aplikasi tertentu',
        appPackageName: 'com.example.app',
        endMinute: 1440,
        priority: 100,
        isEnabled: true,
        createdAt: now,
      ));
      await rules.add(ClassificationRule(
        id: 'rule-higher',
        quotaCategoryId: main.id!,
        ruleName: 'Prioritas tertinggi',
        priority: 200,
        isEnabled: true,
        createdAt: now,
      ));

      final ordered = await rules.getByPackage(packageId);
      expect(
        ordered.map((rule) => rule.id).toList(),
        ['rule-higher', 'rule-specific', 'rule-general'],
      );
    });
  });

  group('InMemoryUsageRepository', () {
    test('catatan otomatis dan manual dapat disimpan terpisah', () async {
      final packages = InMemoryPackageRepository();
      final packageId = await packages.add(createPackage());
      final usage = InMemoryUsageRepository(packages);

      await usage.upsertRecord(
        createUsageRecord(
          packageId: packageId,
          source: UsageSource.android,
          sourceKey: 'android-record-1',
        ),
      );

      await usage.upsertRecordWithAllocations(
        createUsageRecord(
          packageId: packageId,
          source: UsageSource.manual,
          sourceKey: 'manual-record-1',
          scope: UsageRecordScope.manualTotal,
          rxBytes: 200,
          txBytes: 100,
        ),
        (recordId) => [
          UsageAllocation(
            packageId: packageId,
            usageRecordId: recordId,
            allocatedBytes: 300,
            allocationMethod: AllocationMethod.unclassified,
            createdAt: DateTime(2026, 11, 12),
          ),
        ],
      );

      final records = await usage.getRecords(packageId);

      expect(records, hasLength(2));
      expect(
        records.where((record) => record.source == UsageSource.android),
        hasLength(1),
      );
      expect(
        records.where((record) => record.source == UsageSource.manual),
        hasLength(1),
      );
    });

    test('sourceKey yang sama memperbarui catatan yang sudah ada', () async {
      final packages = InMemoryPackageRepository();
      final packageId = await packages.add(createPackage());
      final usage = InMemoryUsageRepository(packages);

      final firstId = await usage.upsertRecord(
        createUsageRecord(packageId: packageId, sourceKey: 'android-record-1'),
      );

      final secondId = await usage.upsertRecord(
        createUsageRecord(
          packageId: packageId,
          sourceKey: 'android-record-1',
          rxBytes: 300,
          txBytes: 200,
        ),
      );

      final records = await usage.getRecords(packageId);

      expect(secondId, firstId);
      expect(records, hasLength(1));
      expect(records.single.totalBytes, 500);
    });

    test('sourceKey tidak boleh digunakan oleh paket berbeda', () async {
      final packages = InMemoryPackageRepository();

      final firstPackageId = await packages.add(createPackage());

      final secondPackageId = await packages.add(createPackage(userId: 'u2'));

      final usage = InMemoryUsageRepository(packages);

      await usage.upsertRecord(
        createUsageRecord(
          packageId: firstPackageId,
          sourceKey: 'shared-source-key',
        ),
      );

      await expectLater(
        usage.upsertRecord(
          createUsageRecord(
            packageId: secondPackageId,
            sourceKey: 'shared-source-key',
          ),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('total alokasi tidak boleh melebihi pemakaian record', () async {
      final packages = InMemoryPackageRepository();
      final packageId = await packages.add(createPackage());
      final usage = InMemoryUsageRepository(packages);

      final record = createUsageRecord(
        packageId: packageId,
        scope: UsageRecordScope.appUsage,
      );

      expect(
        () => usage.upsertRecordWithAllocations(
          record,
          (recordId) => [
            UsageAllocation(
              packageId: packageId,
              usageRecordId: recordId,
              allocatedBytes: 101,
              allocationMethod: AllocationMethod.unclassified,
              createdAt: DateTime(2026, 11, 12),
            ),
          ],
        ),
        throwsA(isA<AppException>()),
      );
    });


    test('alokasi parsial ditolak dan record tidak disimpan', () async {
      final packages = InMemoryPackageRepository();
      final packageId = await packages.add(createPackage());
      final usage = InMemoryUsageRepository(packages);
      final record = createUsageRecord(
        packageId: packageId,
        scope: UsageRecordScope.appUsage,
      );

      await expectLater(
        usage.upsertRecordWithAllocations(
          record,
          (recordId) => [
            UsageAllocation(
              packageId: packageId,
              usageRecordId: recordId,
              allocatedBytes: 99,
              allocationMethod: AllocationMethod.unclassified,
              createdAt: DateTime(2026, 11, 12),
            ),
          ],
        ),
        throwsA(isA<AppException>()),
      );

      expect(await usage.getRecords(packageId), isEmpty);
    });

    test('kategori dengan alokasi tidak dapat dihapus', () async {
      final packages = InMemoryPackageRepository();
      final categories = InMemoryQuotaCategoryRepository(packages);
      final packageId = await packages.add(createPackage());
      final now = DateTime(2026, 11, 12);
      final categoryId = await categories.add(
        QuotaCategory(
          packageId: packageId,
          categoryName: 'Kuota Sosial',
          categoryType: QuotaCategoryType.social,
          capacityBytes: 1000000000,
          isEnabled: true,
          createdAt: now,
        ),
      );
      final usage = InMemoryUsageRepository(packages, categories);
      final recordId = await usage.upsertRecordWithAllocations(
        createUsageRecord(
          packageId: packageId,
          scope: UsageRecordScope.appUsage,
        ),
        (recordId) => [
          UsageAllocation(
            packageId: packageId,
            usageRecordId: recordId,
            quotaCategoryId: categoryId,
            allocatedBytes: 100,
            allocationMethod: AllocationMethod.manualUser,
            createdAt: now,
          ),
        ],
      );

      await expectLater(
        categories.delete(categoryId),
        throwsA(isA<AppException>()),
      );
      expect(await categories.getById(categoryId), isNotNull);
      expect(await usage.getAllocations(recordId), hasLength(1));
    });

    test('menghapus paket ikut menghapus catatan dan alokasi', () async {
      final packages = InMemoryPackageRepository();
      final packageId = await packages.add(createPackage());
      final usage = InMemoryUsageRepository(packages);

      final recordId = await usage.upsertRecordWithAllocations(
        createUsageRecord(
          packageId: packageId,
          scope: UsageRecordScope.appUsage,
        ),
        (recordId) => [
          UsageAllocation(
            packageId: packageId,
            usageRecordId: recordId,
            allocatedBytes: 100,
            allocationMethod: AllocationMethod.unclassified,
            createdAt: DateTime(2026, 11, 12),
          ),
        ],
      );

      await packages.delete(packageId);

      expect(await usage.getRecords(packageId), isEmpty);
      expect(await usage.getAllocations(recordId), isEmpty);
    });
  });
}
