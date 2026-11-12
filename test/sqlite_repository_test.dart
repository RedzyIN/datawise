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
  });

  tearDown(() async {
    await helper.close();
  });

  DataPackage samplePackage() {
    final now = DateTime(2026, 11, 12);
    return DataPackage(
      userId: 'user-1',
      name: 'Paket 20 GB',
      operator: 'Operator',
      totalBytes: 20000000000,
      initialUsedBytes: 0,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 12, 1),
      price: null,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('package creation also creates its main category', () async {
    final id = await packages.add(samplePackage());
    final rows = await categories.getByPackage(id);
    expect(rows, hasLength(1));
    expect(rows.single.type, QuotaCategoryType.main);
    expect(rows.single.quotaBytes, 20000000000);
  });

  test('adding and deleting category rebalances main quota', () async {
    final id = await packages.add(samplePackage());
    final now = DateTime(2026, 11, 12);
    final categoryId = await categories.add(QuotaCategory(
      packageId: id,
      name: 'Kuota Malam',
      type: QuotaCategoryType.night,
      quotaBytes: 5000000000,
      createdAt: now,
      updatedAt: now,
    ));
    var rows = await categories.getByPackage(id);
    final main = rows.singleWhere((c) => c.type == QuotaCategoryType.main);
    expect(main.quotaBytes, 15000000000);

    await categories.delete(categoryId);
    rows = await categories.getByPackage(id);
    expect(rows, hasLength(1));
    expect(rows.single.quotaBytes, 20000000000);
  });

  test('manual usage overrides automatic usage for the same date', () async {
    final id = await packages.add(samplePackage());
    final date = DateTime(2026, 11, 12);
    await usage.upsertRecord(id, date, 900, UsageSource.auto);
    await usage.upsertRecord(id, date, 300, UsageSource.manual);
    expect(await usage.getUsedBytesOn(id, date), 300);
    expect(await usage.getTotalUsedBytes(id), 300);
    expect((await usage.getEffectiveRecords(id)), hasLength(1));
    expect((await usage.getRecords(id)), hasLength(2));
  });

  test('package quota update changes main category remainder', () async {
    final id = await packages.add(samplePackage());
    final original = (await packages.getById(id))!;
    await packages.update(original.copyWith(totalBytes: 25000000000));
    final main = (await categories.getByPackage(id)).single;
    expect(main.quotaBytes, 25000000000);
  });
}
