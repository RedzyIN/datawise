import 'package:datawise/core/db_helper.dart';
import 'package:datawise/features/package/package_format.dart';
import 'package:datawise/features/package/package_provider.dart';
import 'package:datawise/features/package/package_validator.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/sqlite/sqlite_repositories.dart';
import 'package:datawise/services/planner_service.dart' show PlannerService;
import 'package:datawise/services/usage_totals.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pengujian "Kuota Sudah Terpakai" (pemakaian awal paket).
///
/// Baseline disimpan sebagai satu catatan MANUAL_TOTAL ber-`source_key`
/// `initial_<packageId>`, jadi pengujian memakai repository SQLite yang
/// benar-benar menyimpan catatan tersebut.
void main() {
  group('konversi dan sisa kuota awal', () {
    test('tabel total kuota, pemakaian awal, dan sisa awal', () {
      const cases = <(double, double, double)>[
        (7, 0, 7),
        (7, 3.5, 3.5),
        (10, 2, 8),
        (15, 10, 5),
        (7, 7, 0),
      ];

      for (final (totalGb, initialGb, expectedRemainingGb) in cases) {
        final total = quotaBytesFromInput(totalGb, inGigabytes: true);
        final initial = quotaBytesFromInput(initialGb, inGigabytes: true);

        expect(
          remainingInitialBytes(total, initial),
          quotaBytesFromInput(expectedRemainingGb, inGigabytes: true),
          reason: '$totalGb GB - $initialGb GB',
        );
      }
    });

    test(
      'MB dan GB dikonversi dengan basis desimal 1 GB = 1.000.000.000 B',
      () {
        expect(quotaBytesFromInput(3.5, inGigabytes: true), 3500000000);
        expect(quotaBytesFromInput(3500, inGigabytes: false), 3500000000);
        expect(quotaBytesFromInput(500, inGigabytes: false), 500000000);
        expect(quotaBytesFromInput(0, inGigabytes: true), 0);

        // Input negatif tidak pernah menjadi byte negatif.
        expect(quotaBytesFromInput(-2, inGigabytes: true), 0);
      },
    );
  });

  group('validasi pemakaian awal', () {
    DataPackage package(int totalBytes) {
      final now = DateTime(2026, 11, 12);

      return DataPackage(
        userId: 'u1',
        packageName: 'Paket Internet',
        advertisedTotalQuotaBytes: totalBytes,
        startDate: now,
        endDate: now.add(const Duration(days: 30)),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('pemakaian awal negatif ditolak', () {
      expect(
        () => PackageValidator.validateInitialUsage(package(7000000000), -1),
        throwsA(isA<AppException>()),
      );
    });

    test('pemakaian awal melebihi total kuota ditolak', () {
      expect(
        () => PackageValidator.validateInitialUsage(
          package(7000000000),
          7000000001,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('pemakaian awal 0 tetap valid', () {
      expect(
        () => PackageValidator.validateInitialUsage(package(7000000000), 0),
        returnsNormally,
      );
    });

    test('pemakaian awal sama dengan total kuota tetap valid', () {
      expect(
        () => PackageValidator.validateInitialUsage(
          package(7000000000),
          7000000000,
        ),
        returnsNormally,
      );
    });
  });

  group('baseline paket pada database', () {
    late DbHelper helper;
    late SqlitePackageRepository packages;
    late SqliteQuotaCategoryRepository categories;
    late SqliteUsageRepository usage;

    const userId = 'user-initial';
    const gb = 1000000000;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      const path = 'datawise_initial_usage_test.db';
      await databaseFactory.deleteDatabase(path);

      helper = DbHelper.forTesting(path);
      packages = SqlitePackageRepository(helper);
      categories = SqliteQuotaCategoryRepository(helper);
      usage = SqliteUsageRepository(helper);

      final db = await helper.database;

      await db.insert('users', {
        'id': userId,
        'display_name': 'Pengguna Tes',
        'email': 'tes@example.com',
        'created_at': DateTime(2026, 11, 1).toIso8601String(),
        'updated_at': DateTime(2026, 11, 1).toIso8601String(),
      });
    });

    tearDown(() async {
      await helper.close();
    });

    DataPackage buildPackage({
      String name = 'Paket Internet',
      int quotaBytes = 7 * gb,
      int startedDaysAgo = 10,
    }) {
      final now = DateTime.now();

      return DataPackage(
        userId: userId,
        packageName: name,
        advertisedTotalQuotaBytes: quotaBytes,
        startDate: dateOnly(now.subtract(Duration(days: startedDaysAgo))),
        endDate: dateOnly(now.add(const Duration(days: 20))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('pemakaian awal tersimpan sebagai baseline tunggal', () async {
      final id = await packages.add(
        buildPackage(),
        initialUsedBytes: 3500000000,
      );

      final records = await usage.getRecords(id);

      expect(records, hasLength(1));
      expect(records.single.source, UsageSource.manual);
      expect(records.single.recordScope, UsageRecordScope.manualTotal);
      expect(records.single.sourceKey, 'initial_$id');

      expect(initialBaselineBytes(records), 3500000000);
      expect(totalEffectiveUsageBytes(records), 3500000000);
    });

    test('statistik otomatis tidak menghitung baseline dua kali', () async {
      final id = await packages.add(
        buildPackage(),
        initialUsedBytes: 3500000000,
      );

      final now = DateTime.now();
      final today = dateOnly(now);

      // Pemakaian hasil pemantauan DATAWISE (tanggal berbeda dari mulai paket).
      await usage.upsertRecord(
        UsageRecord(
          packageId: id,
          recordScope: UsageRecordScope.deviceTotal,
          networkType: NetworkType.mobile,
          periodStartAt: today,
          periodEndAt: today.add(const Duration(hours: 1)),
          rxBytes: 500000000,
          txBytes: 0,
          source: UsageSource.android,
          // Skema v3 mewajibkan source_key untuk catatan non-manual.
          sourceKey: 'android_device_total_${id}_${dateToDb(today)}',
          recordedAt: now,
        ),
      );

      final records = await usage.getRecords(id);

      expect(initialBaselineBytes(records), 3500000000);
      expect(totalEffectiveUsageBytes(records), 4000000000);
    });

    test('provider, Dashboard, dan Planner memakai angka yang sama', () async {
      final id = await packages.add(
        buildPackage(),
        initialUsedBytes: 3500000000,
      );

      final provider = PackageProvider(packages, usageRepo: usage);
      await provider.load(userId);

      final package = provider.packages.single;

      expect(provider.initialUsedFor(id), 3500000000);
      expect(provider.usedBytesFor(id), 3500000000);
      expect(provider.remainingBytesFor(package), 3500000000);

      final plan = PlannerService.calculate(
        package: package,
        totalUsedBytes: provider.usedBytesFor(id),
        todayUsedBytes: 0,
        today: DateTime.now(),
      );

      expect(plan.usedBytes, 3500000000);
      expect(plan.remainingBytes, provider.remainingBytesFor(package));
    });

    test('paket berbeda tidak saling memengaruhi', () async {
      final packageA = await packages.add(
        buildPackage(name: 'Paket A'),
        initialUsedBytes: 3500000000,
      );
      final packageB = await packages.add(
        buildPackage(name: 'Paket B', quotaBytes: 15 * gb),
      );

      final provider = PackageProvider(packages, usageRepo: usage);
      await provider.load(userId);

      expect(provider.usedBytesFor(packageA), 3500000000);
      expect(provider.usedBytesFor(packageB), 0);
      expect(provider.initialUsedFor(packageA), 3500000000);
      expect(provider.initialUsedFor(packageB), 0);
      expect(provider.remainingBytesFor(provider.findById(packageB)!), 15 * gb);
    });

    test('edit paket tidak menggandakan pemakaian awal', () async {
      final id = await packages.add(
        buildPackage(),
        initialUsedBytes: 3500000000,
      );

      final stored = (await packages.getById(id))!;

      await packages.update(
        stored.copyWith(
          packageName: 'Paket Internet Baru',
          operatorName: 'XL',
          updatedAt: DateTime.now(),
        ),
      );

      final records = await usage.getRecords(id);

      expect(records, hasLength(1));
      expect(initialBaselineBytes(records), 3500000000);

      final provider = PackageProvider(packages, usageRepo: usage);
      await provider.load(userId);

      expect(provider.usedBytesFor(id), 3500000000);
      expect(provider.initialUsedFor(id), 3500000000);
    });

    test('pemakaian awal hanya dibebankan ke kategori utama', () async {
      final now = DateTime.now();
      final id = await packages.addWithCategories(
        buildPackage(quotaBytes: 12 * gb),
        categories: [
          QuotaCategory(
            packageId: '',
            categoryName: 'Kuota Malam',
            categoryType: QuotaCategoryType.night,
            capacityBytes: 5 * gb,
            isEnabled: true,
            createdAt: now,
          ),
        ],
        initialUsedBytes: 3500000000,
      );

      final packageCategories = await categories.getByPackage(id);
      final main = packageCategories.firstWhere(
        (category) => category.categoryType == QuotaCategoryType.main,
      );
      final night = packageCategories.firstWhere(
        (category) => category.categoryType == QuotaCategoryType.night,
      );

      final allocations = await usage.getAllocationsByPackage(id);

      expect(allocations, hasLength(1));
      expect(allocations.single.quotaCategoryId, main.id);
      expect(allocations.single.allocatedBytes, 3500000000);
      expect(
        allocations.where(
          (allocation) => allocation.quotaCategoryId == night.id,
        ),
        isEmpty,
      );

      // Baseline tidak menambah total pemakaian per kategori maupun total paket.
      expect(totalEffectiveUsageBytes(await usage.getRecords(id)), 3500000000);
    });
  });
}
