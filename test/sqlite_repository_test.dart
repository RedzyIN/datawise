import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datawise/core/db_helper.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/sqlite/sqlite_repositories.dart';

void main() {
  late DbHelper helper;
  late SqlitePackageRepository packages;
  late SqliteQuotaCategoryRepository categories;
  late SqliteUsageRepository usage;
  late SqliteClassificationRuleRepository dbRules;

  const userId = 'user-1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    const path = 'datawise_repository_test.db';
    await databaseFactory.deleteDatabase(path);

    helper = DbHelper.forTesting(path);

    packages = SqlitePackageRepository(helper);
    categories = SqliteQuotaCategoryRepository(helper);
    usage = SqliteUsageRepository(helper);
    dbRules = SqliteClassificationRuleRepository(helper);

    // Skema v3 mewajibkan pengguna tersedia sebelum paket dibuat.
    final db = await helper.database;

    await db.insert('users', {
      'id': userId,
      'display_name': 'Pengguna Tes',
      'email': 'test@example.com',
      'created_at': DateTime(2026, 11, 12).toIso8601String(),
      'updated_at': DateTime(2026, 11, 12).toIso8601String(),
    });
  });

  tearDown(() async {
    await helper.close();
  });

  DataPackage samplePackage({
    PackageStatus status = PackageStatus.active,
    String ownerId = userId,
    int quotaBytes = 20000000000,
  }) {
    final now = DateTime(2026, 11, 12);

    return DataPackage(
      userId: ownerId,
      packageName: 'Paket 20 GB',
      operatorName: 'Operator',
      advertisedTotalQuotaBytes: quotaBytes,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 12, 1),
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  UsageRecord sampleUsage({
    required String packageId,
    UsageRecordScope scope = UsageRecordScope.deviceTotal,
    UsageSource source = UsageSource.android,
    String? sourceKey = 'android-record-1',
    NetworkType networkType = NetworkType.mobile,
    int rxBytes = 600,
    int txBytes = 400,
    String? appPackageName,
  }) {
    final start = DateTime(2026, 11, 12);
    final end = DateTime(2026, 11, 13);

    return UsageRecord(
      packageId: packageId,
      recordScope: scope,
      appPackageName: appPackageName,
      networkType: networkType,
      periodStartAt: start,
      periodEndAt: end,
      rxBytes: rxBytes,
      txBytes: txBytes,
      source: source,
      sourceKey: sourceKey,
      recordedAt: end,
    );
  }

  test('package creation also creates its main category', () async {
    final id = await packages.add(samplePackage());

    final package = await packages.getById(id);
    final rows = await categories.getByPackage(id);

    expect(package, isNotNull);
    expect(package!.packageName, 'Paket 20 GB');
    expect(rows, hasLength(1));
    expect(rows.single.categoryType, QuotaCategoryType.main);
    expect(rows.single.capacityBytes, 20000000000);
  });

  test('only one active package is allowed per user', () async {
    final firstId = await packages.add(samplePackage());

    final secondId = await packages.add(samplePackage());

    expect((await packages.getById(firstId))!.status, PackageStatus.inactive);

    expect((await packages.getById(secondId))!.status, PackageStatus.active);

    expect((await packages.getActive(userId))!.id, secondId);
  });

  test('adding and deleting category rebalances main quota', () async {
    final packageId = await packages.add(samplePackage());
    final now = DateTime(2026, 11, 12);

    final categoryId = await categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: 'Kuota Malam',
        categoryType: QuotaCategoryType.night,
        capacityBytes: 5000000000,
        isEnabled: true,
        createdAt: now,
      ),
    );

    var rows = await categories.getByPackage(packageId);

    final main = rows.singleWhere(
      (category) => category.categoryType == QuotaCategoryType.main,
    );

    expect(main.capacityBytes, 15000000000);

    await categories.delete(categoryId);

    rows = await categories.getByPackage(packageId);

    expect(rows, hasLength(1));
    expect(rows.single.capacityBytes, 20000000000);
  });

  test('updating category quota rebalances main quota', () async {
    final packageId = await packages.add(samplePackage());
    final now = DateTime(2026, 11, 12);

    final categoryId = await categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: 'Kuota Malam',
        categoryType: QuotaCategoryType.night,
        capacityBytes: 5000000000,
        isEnabled: true,
        createdAt: now,
      ),
    );

    final category = (await categories.getById(categoryId))!;

    await categories.update(
      QuotaCategory(
        id: category.id,
        packageId: packageId,
        categoryName: category.categoryName,
        categoryType: category.categoryType,
        capacityBytes: 7000000000,
        isEnabled: category.isEnabled,
        createdAt: category.createdAt,
      ),
    );

    var rows = await categories.getByPackage(packageId);

    expect(
      rows
          .singleWhere((item) => item.categoryType == QuotaCategoryType.main)
          .capacityBytes,
      13000000000,
    );

    final updated = (await categories.getById(categoryId))!;

    await categories.update(
      QuotaCategory(
        id: updated.id,
        packageId: packageId,
        categoryName: updated.categoryName,
        categoryType: updated.categoryType,
        capacityBytes: 3000000000,
        isEnabled: updated.isEnabled,
        createdAt: updated.createdAt,
      ),
    );

    rows = await categories.getByPackage(packageId);

    expect(
      rows
          .singleWhere((item) => item.categoryType == QuotaCategoryType.main)
          .capacityBytes,
      17000000000,
    );
  });

  test('package quota update changes main category capacity', () async {
    final packageId = await packages.add(samplePackage());

    final original = (await packages.getById(packageId))!;

    await packages.update(
      original.copyWith(advertisedTotalQuotaBytes: 25000000000),
    );

    final main = (await categories.getByPackage(packageId)).single;

    expect(main.capacityBytes, 25000000000);
  });

  test('package quota cannot be smaller than additional categories', () async {
    final packageId = await packages.add(samplePackage());
    final now = DateTime(2026, 11, 12);

    await categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: 'Kuota Malam',
        categoryType: QuotaCategoryType.night,
        capacityBytes: 5000000000,
        isEnabled: true,
        createdAt: now,
      ),
    );

    final original = (await packages.getById(packageId))!;

    expect(
      () => packages.update(
        original.copyWith(advertisedTotalQuotaBytes: 4000000000),
      ),
      throwsA(isA<AppException>()),
    );
  });

  test('classification rule order honors PRD priority and specificity', () async {
    final packageId = await packages.add(samplePackage());
    final main = (await categories.getByPackage(packageId)).single;
    final now = DateTime(2026, 11, 15);

    await dbRules.add(ClassificationRule(
      id: 'rule-general',
      quotaCategoryId: main.id!,
      ruleName: 'Semua aplikasi',
      priority: 100,
      isEnabled: true,
      createdAt: now,
    ));
    await dbRules.add(ClassificationRule(
      id: 'rule-specific',
      quotaCategoryId: main.id!,
      ruleName: 'Aplikasi tertentu',
      appPackageName: 'com.example.app',
      endMinute: 1440,
      priority: 100,
      isEnabled: true,
      createdAt: now,
    ));
    await dbRules.add(ClassificationRule(
      id: 'rule-higher',
      quotaCategoryId: main.id!,
      ruleName: 'Prioritas tertinggi',
      priority: 200,
      isEnabled: true,
      createdAt: now,
    ));

    final ordered = await dbRules.getByPackage(packageId);
    expect(
      ordered.map((rule) => rule.id).toList(),
      ['rule-higher', 'rule-specific', 'rule-general'],
    );
  });

  test(
    'usage records from automatic and manual sources stay separate',
    () async {
      final packageId = await packages.add(samplePackage());

      await usage.upsertRecord(
        sampleUsage(
          packageId: packageId,
          source: UsageSource.android,
          sourceKey: 'android-record-1',
        ),
      );

      await usage.upsertRecordWithAllocations(
        sampleUsage(
          packageId: packageId,
          source: UsageSource.manual,
          sourceKey: null,
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
    },
  );

  test('same sourceKey updates the existing usage record', () async {
    final packageId = await packages.add(samplePackage());

    final firstId = await usage.upsertRecord(
      sampleUsage(packageId: packageId, sourceKey: 'android-record-1'),
    );

    final secondId = await usage.upsertRecord(
      sampleUsage(
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
    final db = await helper.database;

    await db.insert('users', {
      'id': 'user-2',
      'display_name': 'Pengguna Kedua',
      'email': 'test2@example.com',
      'created_at': DateTime(2026, 11, 12).toIso8601String(),
      'updated_at': DateTime(2026, 11, 12).toIso8601String(),
    });

    final firstPackageId = await packages.add(samplePackage(ownerId: userId));

    final secondPackageId = await packages.add(
      samplePackage(ownerId: 'user-2'),
    );

    await usage.upsertRecord(
      sampleUsage(packageId: firstPackageId, sourceKey: 'shared-source-key'),
    );

    await expectLater(
      usage.upsertRecord(
        sampleUsage(packageId: secondPackageId, sourceKey: 'shared-source-key'),
      ),
      throwsA(isA<AppException>()),
    );

    expect(await usage.getRecords(firstPackageId), hasLength(1));
    expect(await usage.getRecords(secondPackageId), isEmpty);
  });

  test('usage records can be filtered by overlapping period', () async {
    final packageId = await packages.add(samplePackage());

    await usage.upsertRecord(
      sampleUsage(packageId: packageId, sourceKey: 'android-record-1'),
    );

    final records = await usage.getRecordsForPeriod(
      packageId,
      DateTime(2026, 11, 12, 12),
      DateTime(2026, 11, 14),
    );

    expect(records, hasLength(1));
  });

  test('manual records can be deleted by period', () async {
    final packageId = await packages.add(samplePackage());

    await usage.upsertRecordWithAllocations(
      sampleUsage(
        packageId: packageId,
        source: UsageSource.manual,
        sourceKey: null,
        scope: UsageRecordScope.manualTotal,
      ),
      (recordId) => [
        UsageAllocation(
          packageId: packageId,
          usageRecordId: recordId,
          allocatedBytes: 1000,
          allocationMethod: AllocationMethod.unclassified,
          createdAt: DateTime(2026, 11, 12),
        ),
      ],
    );

    await usage.deleteManualRecords(
      packageId,
      DateTime(2026, 11, 12),
      DateTime(2026, 11, 13),
    );

    expect(await usage.getRecords(packageId), isEmpty);
  });

  test('category with allocation cannot be deleted', () async {
    final packageId = await packages.add(samplePackage());
    final now = DateTime(2026, 11, 12);
    final categoryId = await categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: 'Kuota Sosial',
        categoryType: QuotaCategoryType.social,
        capacityBytes: 5000000000,
        isEnabled: true,
        createdAt: now,
      ),
    );

    await usage.upsertRecordWithAllocations(
      sampleUsage(
        packageId: packageId,
        scope: UsageRecordScope.appUsage,
        appPackageName: 'com.example.app',
      ),
      (recordId) => [
        UsageAllocation(
          packageId: packageId,
          usageRecordId: recordId,
          quotaCategoryId: categoryId,
          allocatedBytes: 1000,
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
  });

  test('app usage allocations can be saved and retrieved', () async {
    final packageId = await packages.add(samplePackage());
    final now = DateTime(2026, 11, 12);

    final categoryId = await categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: 'Kuota Sosial',
        categoryType: QuotaCategoryType.social,
        capacityBytes: 5000000000,
        isEnabled: true,
        createdAt: now,
      ),
    );

    final record = sampleUsage(
      packageId: packageId,
      scope: UsageRecordScope.appUsage,
      appPackageName: 'com.example.app',
    );
    final recordId = await usage.upsertRecordWithAllocations(
      record,
      (recordId) => [
        UsageAllocation(
          packageId: packageId,
          usageRecordId: recordId,
          quotaCategoryId: categoryId,
          allocatedBytes: 1000,
          allocationMethod: AllocationMethod.manualUser,
          createdAt: now,
        ),
      ],
    );

    final allocations = await usage.getAllocations(recordId);

    expect(allocations, hasLength(1));
    expect(allocations.single.allocatedBytes, 1000);
    expect(allocations.single.quotaCategoryId, categoryId);
  });

  test('allocation cannot exceed usage record total', () async {
    final packageId = await packages.add(samplePackage());

    final record = sampleUsage(
      packageId: packageId,
      scope: UsageRecordScope.appUsage,
      appPackageName: 'com.example.app',
    );
    final now = DateTime(2026, 11, 12);

    expect(
      () => usage.upsertRecordWithAllocations(
        record,
        (recordId) => [
          UsageAllocation(
            packageId: packageId,
            usageRecordId: recordId,
            allocatedBytes: 1001,
            allocationMethod: AllocationMethod.unclassified,
            createdAt: now,
          ),
        ],
      ),
      throwsA(isA<AppException>()),
    );
  });


  test('allocation total must equal usage record total', () async {
    final packageId = await packages.add(samplePackage());
    final record = sampleUsage(
      packageId: packageId,
      scope: UsageRecordScope.appUsage,
      appPackageName: 'com.example.app',
    );

    await expectLater(
      usage.upsertRecordWithAllocations(
        record,
        (recordId) => [
          UsageAllocation(
            packageId: packageId,
            usageRecordId: recordId,
            allocatedBytes: 999,
            allocationMethod: AllocationMethod.unclassified,
            createdAt: DateTime(2026, 11, 12),
          ),
        ],
      ),
      throwsA(isA<AppException>()),
    );
    expect(await usage.getRecords(packageId), isEmpty);
  });

  test('device total records cannot have allocations', () async {
    final packageId = await packages.add(samplePackage());

    final recordId = await usage.upsertRecord(
      sampleUsage(packageId: packageId),
    );

    expect(
      () => usage.replaceAllocations(recordId, [
        UsageAllocation(
          packageId: packageId,
          usageRecordId: recordId,
          allocatedBytes: 100,
          allocationMethod: AllocationMethod.unclassified,
          createdAt: DateTime(2026, 11, 12),
        ),
      ]),
      throwsA(isA<AppException>()),
    );
  });

  test(
    'deleting package also deletes its categories and usage records',
    () async {
      final packageId = await packages.add(samplePackage());

      await usage.upsertRecord(sampleUsage(packageId: packageId));

      await packages.delete(packageId);

      expect(await packages.getById(packageId), isNull);
      expect(await categories.getByPackage(packageId), isEmpty);
      expect(await usage.getRecords(packageId), isEmpty);
    },
  );
}
