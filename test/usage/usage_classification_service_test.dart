import 'package:datawise/core/db_helper.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:datawise/repositories/sqlite/sqlite_repositories.dart';
import 'package:datawise/repositories/usage_repository.dart';
import 'package:datawise/services/usage/classification_engine.dart';
import 'package:datawise/services/usage/usage_classification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _gb = 1000000000;
const _userId = 'user-1';

abstract class _Backend {
  Future<void> setUp();
  Future<void> tearDown();

  Future<String> createPackage({
    String name = 'Paket 20 GB',
    int quotaBytes = 20 * _gb,
    PackageStatus status = PackageStatus.active,
    DateTime? startDate,
    DateTime? endDate,
  });

  Future<QuotaCategory> mainOf(String packageId);
  Future<QuotaCategory?> categoryById(String categoryId);

  Future<String> addCategory(
    String packageId, {
    String name = 'Kuota Malam',
    QuotaCategoryType type = QuotaCategoryType.night,
    int capacityBytes = 5 * _gb,
    DateTime? validFrom,
    DateTime? validUntil,
  });

  Future<String> addRule({
    required String packageId,
    required String categoryId,
    String? appPackageName,
    int? startMinute,
    int? endMinute,
    int daysOfWeekMask = 127,
    int priority = 0,
    bool isEnabled = true,
  });

  UsageClassificationService service();
  UsageRepository get usage;
}

class _InMemoryBackend implements _Backend {
  late InMemoryPackageRepository packages;
  late InMemoryQuotaCategoryRepository categories;
  late InMemoryClassificationRuleRepository rules;
  late InMemoryUsageRepository usageRepo;

  @override
  Future<void> setUp() async {
    packages = InMemoryPackageRepository();
    categories = InMemoryQuotaCategoryRepository(packages);
    rules = InMemoryClassificationRuleRepository(packages, categories);
    usageRepo = InMemoryUsageRepository(packages, categories, rules);
  }

  @override
  Future<void> tearDown() async {}

  @override
  Future<String> createPackage({
    String name = 'Paket 20 GB',
    int quotaBytes = 20 * _gb,
    PackageStatus status = PackageStatus.active,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final now = DateTime.now();

    return packages.add(
      DataPackage(
        userId: _userId,
        packageName: name,
        operatorName: 'Operator',
        advertisedTotalQuotaBytes: quotaBytes,
        startDate: startDate ?? now.subtract(const Duration(days: 1)),
        endDate: endDate ?? now.add(const Duration(days: 30)),
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<QuotaCategory> mainOf(String packageId) async {
    final rows = await categories.getByPackage(packageId);
    return rows.singleWhere(
      (item) => item.categoryType == QuotaCategoryType.main,
    );
  }

  @override
  Future<QuotaCategory?> categoryById(String categoryId) =>
      categories.getById(categoryId);

  @override
  Future<String> addCategory(
    String packageId, {
    String name = 'Kuota Malam',
    QuotaCategoryType type = QuotaCategoryType.night,
    int capacityBytes = 5 * _gb,
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: name,
        categoryType: type,
        capacityBytes: capacityBytes,
        validFrom: validFrom,
        validUntil: validUntil,
        isEnabled: true,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<String> addRule({
    required String packageId,
    required String categoryId,
    String? appPackageName,
    int? startMinute,
    int? endMinute,
    int daysOfWeekMask = 127,
    int priority = 0,
    bool isEnabled = true,
  }) {
    return rules.add(
      ClassificationRule(
        quotaCategoryId: categoryId,
        ruleName: 'Aturan',
        appPackageName: appPackageName,
        startMinute: startMinute,
        endMinute: endMinute,
        daysOfWeekMask: daysOfWeekMask,
        priority: priority,
        isEnabled: isEnabled,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  UsageClassificationService service() => UsageClassificationService(
    ruleRepository: rules,
    categoryRepository: categories,
    usageRepository: usageRepo,
  );

  @override
  UsageRepository get usage => usageRepo;
}

class _SqliteBackend implements _Backend {
  static const _path = 'datawise_usage_classification_test.db';

  late DbHelper helper;
  late SqlitePackageRepository packages;
  late SqliteQuotaCategoryRepository categories;
  late SqliteClassificationRuleRepository rules;
  late SqliteUsageRepository usageRepo;

  @override
  Future<void> setUp() async {
    await databaseFactory.deleteDatabase(_path);

    helper = DbHelper.forTesting(_path);
    packages = SqlitePackageRepository(helper);
    categories = SqliteQuotaCategoryRepository(helper);
    rules = SqliteClassificationRuleRepository(helper);
    usageRepo = SqliteUsageRepository(helper);

    final db = await helper.database;
    final now = DateTime(2026, 11, 12).toIso8601String();

    await db.insert('users', {
      'id': _userId,
      'display_name': 'Pengguna Tes',
      'email': 'test@example.com',
      'created_at': now,
      'updated_at': now,
    });
  }

  @override
  Future<void> tearDown() => helper.close();

  @override
  Future<String> createPackage({
    String name = 'Paket 20 GB',
    int quotaBytes = 20 * _gb,
    PackageStatus status = PackageStatus.active,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final now = DateTime.now();

    return packages.add(
      DataPackage(
        userId: _userId,
        packageName: name,
        operatorName: 'Operator',
        advertisedTotalQuotaBytes: quotaBytes,
        startDate: startDate ?? now.subtract(const Duration(days: 1)),
        endDate: endDate ?? now.add(const Duration(days: 30)),
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<QuotaCategory> mainOf(String packageId) async {
    final rows = await categories.getByPackage(packageId);
    return rows.singleWhere(
      (item) => item.categoryType == QuotaCategoryType.main,
    );
  }

  @override
  Future<QuotaCategory?> categoryById(String categoryId) =>
      categories.getById(categoryId);

  @override
  Future<String> addCategory(
    String packageId, {
    String name = 'Kuota Malam',
    QuotaCategoryType type = QuotaCategoryType.night,
    int capacityBytes = 5 * _gb,
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return categories.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: name,
        categoryType: type,
        capacityBytes: capacityBytes,
        validFrom: validFrom,
        validUntil: validUntil,
        isEnabled: true,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<String> addRule({
    required String packageId,
    required String categoryId,
    String? appPackageName,
    int? startMinute,
    int? endMinute,
    int daysOfWeekMask = 127,
    int priority = 0,
    bool isEnabled = true,
  }) {
    return rules.add(
      ClassificationRule(
        quotaCategoryId: categoryId,
        ruleName: 'Aturan',
        appPackageName: appPackageName,
        startMinute: startMinute,
        endMinute: endMinute,
        daysOfWeekMask: daysOfWeekMask,
        priority: priority,
        isEnabled: isEnabled,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  UsageClassificationService service() => UsageClassificationService(
    ruleRepository: rules,
    categoryRepository: categories,
    usageRepository: usageRepo,
  );

  @override
  UsageRepository get usage => usageRepo;
}

UsageRecord _appUsage(
  String packageId, {
  String app = 'com.instagram.android',
  int rx = 800,
  int tx = 200,
  DateTime? at,
  String sourceKey = 'usage-key-1',
}) {
  final start = at ?? DateTime.now();

  return UsageRecord(
    packageId: packageId,
    recordScope: UsageRecordScope.appUsage,
    appPackageName: app,
    appName: 'Instagram',
    networkType: NetworkType.mobile,
    periodStartAt: start,
    periodEndAt: start.add(const Duration(minutes: 5)),
    rxBytes: rx,
    txBytes: tx,
    source: UsageSource.android,
    sourceKey: sourceKey,
    recordedAt: start,
  );
}

UsageAllocation _allocation(
  UsageRecord record,
  String usageRecordId, {
  required AllocationMethod method,
  String? categoryId,
  String? ruleId,
  int? allocatedBytes,
}) {
  return UsageAllocation(
    packageId: record.packageId,
    usageRecordId: usageRecordId,
    quotaCategoryId: categoryId,
    classificationRuleId: ruleId,
    allocatedBytes: allocatedBytes ?? record.totalBytes,
    allocationMethod: method,
    createdAt: DateTime.now(),
  );
}

void _runScenarios(_Backend Function() factory, String label) {
  group(label, () {
    late _Backend backend;

    setUp(() async {
      backend = factory();
      await backend.setUp();
    });

    tearDown(() async {
      await backend.tearDown();
    });

    test(
      'aturan cocok menghasilkan AUTO_RULE dengan kategori dan aturan',
      () async {
        final packageId = await backend.createPackage();
        final categoryId = await backend.addCategory(packageId);
        final ruleId = await backend.addRule(
          packageId: packageId,
          categoryId: categoryId,
          appPackageName: 'com.instagram.android',
          startMinute: 0,
          endMinute: 1440,
        );

        final stored = await backend.service().classifyAndStore(
          _appUsage(packageId),
        );

        expect(
          stored.classification.outcome,
          ClassificationOutcome.matchedRule,
        );

        final allocations = await backend.usage.getAllocations(
          stored.usageRecordId,
        );

        expect(allocations, hasLength(1));

        final allocation = allocations.single;

        expect(allocation.allocationMethod, AllocationMethod.autoRule);
        expect(allocation.quotaCategoryId, categoryId);
        expect(allocation.classificationRuleId, ruleId);
        expect(allocation.packageId, packageId);
        expect(allocation.allocatedBytes, 1000);
      },
    );

    test('tanpa aturan cocok menghasilkan MAIN_FALLBACK', () async {
      final packageId = await backend.createPackage();
      final main = await backend.mainOf(packageId);

      final stored = await backend.service().classifyAndStore(
        _appUsage(packageId),
      );

      expect(stored.classification.outcome, ClassificationOutcome.mainFallback);

      final allocation = (await backend.usage.getAllocations(
        stored.usageRecordId,
      )).single;

      expect(allocation.allocationMethod, AllocationMethod.mainFallback);
      expect(allocation.quotaCategoryId, main.id);
      expect(allocation.classificationRuleId, isNull);
      expect(allocation.allocatedBytes, 1000);
    });

    test('tanpa kategori valid menghasilkan UNCLASSIFIED', () async {
      final now = DateTime.now();
      final packageId = await backend.createPackage(
        status: PackageStatus.inactive,
        startDate: dateOnly(now).add(const Duration(days: 10)),
        endDate: dateOnly(now).add(const Duration(days: 40)),
      );

      final stored = await backend.service().classifyAndStore(
        _appUsage(packageId),
      );

      expect(stored.classification.outcome, ClassificationOutcome.unclassified);
      expect(
        stored.classification.unclassifiedReason,
        UnclassifiedReason.noValidCategory,
      );

      final allocation = (await backend.usage.getAllocations(
        stored.usageRecordId,
      )).single;

      expect(allocation.allocationMethod, AllocationMethod.unclassified);
      expect(allocation.quotaCategoryId, isNull);
      expect(allocation.classificationRuleId, isNull);
      expect(allocation.allocatedBytes, 1000);
    });

    test('allocatedBytes sama dengan RX ditambah TX', () async {
      final packageId = await backend.createPackage();
      final categoryId = await backend.addCategory(packageId);
      await backend.addRule(
        packageId: packageId,
        categoryId: categoryId,
        startMinute: 0,
        endMinute: 1440,
      );

      final record = _appUsage(packageId, rx: 1200, tx: 300);
      final stored = await backend.service().classifyAndStore(record);

      expect(record.totalBytes, 1500);
      expect(stored.allocation.allocatedBytes, 1500);

      final saved = await backend.usage.getById(stored.usageRecordId);

      expect(saved?.rxBytes, 1200);
      expect(saved?.txBytes, 300);
    });

    test('pencatatan penggunaan tidak mengubah kapasitas kategori', () async {
      final packageId = await backend.createPackage();
      final categoryId = await backend.addCategory(packageId);
      final mainBefore = await backend.mainOf(packageId);

      await backend.addRule(
        packageId: packageId,
        categoryId: categoryId,
        startMinute: 0,
        endMinute: 1440,
      );

      await backend.service().classifyAndStore(_appUsage(packageId));

      expect((await backend.categoryById(categoryId))?.capacityBytes, 5 * _gb);
      expect(
        (await backend.mainOf(packageId)).capacityBytes,
        mainBefore.capacityBytes,
      );
    });

    test('kegagalan penyimpanan alokasi membatalkan UsageRecord', () async {
      final packageId = await backend.createPackage();
      final record = _appUsage(packageId, sourceKey: 'rollback-key');

      await expectLater(
        backend.usage.upsertRecordWithAllocations(
          record,
          (id) => [
            _allocation(
              record,
              id,
              method: AllocationMethod.unclassified,
              allocatedBytes: record.totalBytes + 1,
            ),
          ],
        ),
        throwsA(isA<AppException>()),
      );

      expect(await backend.usage.getRecords(packageId), isEmpty);
      expect(await backend.usage.getAllocationsByPackage(packageId), isEmpty);
    });

    test('upsert record yang sama tidak menggandakan alokasi', () async {
      final packageId = await backend.createPackage();
      final categoryId = await backend.addCategory(packageId);

      await backend.addRule(
        packageId: packageId,
        categoryId: categoryId,
        startMinute: 0,
        endMinute: 1440,
      );

      final service = backend.service();

      final first = await service.classifyAndStore(
        _appUsage(packageId, rx: 400, tx: 100, sourceKey: 'same-key'),
      );
      final second = await service.classifyAndStore(
        _appUsage(packageId, rx: 900, tx: 100, sourceKey: 'same-key'),
      );

      expect(second.usageRecordId, first.usageRecordId);
      expect(await backend.usage.getRecords(packageId), hasLength(1));

      final allocations = await backend.usage.getAllocations(
        second.usageRecordId,
      );

      expect(allocations, hasLength(1));
      expect(allocations.single.allocatedBytes, 1000);
      expect(allocations.single.quotaCategoryId, categoryId);
    });

    test('catatan agregat perangkat ditolak tanpa menyimpan record', () async {
      final packageId = await backend.createPackage();
      final start = DateTime.now();

      final record = UsageRecord(
        packageId: packageId,
        recordScope: UsageRecordScope.deviceTotal,
        networkType: NetworkType.mobile,
        periodStartAt: start,
        periodEndAt: start.add(const Duration(minutes: 5)),
        rxBytes: 500,
        txBytes: 500,
        source: UsageSource.android,
        sourceKey: 'device-key',
        recordedAt: start,
      );

      await expectLater(
        backend.service().classifyAndStore(record),
        throwsA(isA<AppException>()),
      );

      expect(await backend.usage.getRecords(packageId), isEmpty);
    });

    test('kategori paket lain tidak dapat dipakai alokasi', () async {
      final packageA = await backend.createPackage(name: 'Paket A');
      final packageB = await backend.createPackage(
        name: 'Paket B',
        status: PackageStatus.inactive,
      );
      final foreignCategory = await backend.addCategory(packageA);
      final record = _appUsage(packageB, sourceKey: 'foreign-key');

      await expectLater(
        backend.usage.upsertRecordWithAllocations(
          record,
          (id) => [
            _allocation(
              record,
              id,
              method: AllocationMethod.manualUser,
              categoryId: foreignCategory,
            ),
          ],
        ),
        throwsA(isA<AppException>()),
      );

      expect(await backend.usage.getRecords(packageB), isEmpty);
      expect(await backend.usage.getAllocationsByPackage(packageA), isEmpty);
    });
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  _runScenarios(_InMemoryBackend.new, 'InMemory');
  _runScenarios(_SqliteBackend.new, 'SQLite');
}
