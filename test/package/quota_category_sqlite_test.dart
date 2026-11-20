import 'package:datawise/core/db_helper.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/sqlite/sqlite_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const path = 'datawise_quota_category_test.db';
  const gb = 1000000000;
  const userId = 'user-1';

  late DbHelper helper;
  late SqlitePackageRepository packages;
  late SqliteQuotaCategoryRepository categories;

  Future<void> openDatabase() async {
    helper = DbHelper.forTesting(path);
    packages = SqlitePackageRepository(helper);
    categories = SqliteQuotaCategoryRepository(helper);

    final db = await helper.database;
    final now = DateTime(2026, 11, 12).toIso8601String();

    await db.insert('users', {
      'id': userId,
      'display_name': 'Pengguna Tes',
      'email': 'test@example.com',
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await databaseFactory.deleteDatabase(path);
    await openDatabase();
  });

  tearDown(() async {
    await helper.close();
  });

  Future<String> createPackage({
    String name = 'Paket 20 GB',
    int quotaBytes = 20 * gb,
    PackageStatus status = PackageStatus.active,
  }) {
    final now = DateTime.now();

    return packages.add(
      DataPackage(
        userId: userId,
        packageName: name,
        operatorName: 'Operator',
        advertisedTotalQuotaBytes: quotaBytes,
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 30)),
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  QuotaCategory category(
    String packageId, {
    String name = 'Kuota Malam',
    QuotaCategoryType type = QuotaCategoryType.night,
    int capacityBytes = 5 * gb,
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return QuotaCategory(
      packageId: packageId,
      categoryName: name,
      categoryType: type,
      capacityBytes: capacityBytes,
      validFrom: validFrom,
      validUntil: validUntil,
      isEnabled: true,
      createdAt: DateTime(2026, 11, 12),
    );
  }

  Future<int> mainCapacity(String packageId) async {
    final rows = await categories.getByPackage(packageId);

    return rows
        .singleWhere((item) => item.categoryType == QuotaCategoryType.main)
        .capacityBytes;
  }

  test('tanggal berakhir sebelum tanggal mulai ditolak', () async {
    final packageId = await createPackage();

    await expectLater(
      categories.add(
        category(
          packageId,
          validFrom: DateTime(2026, 12, 1),
          validUntil: DateTime(2026, 11, 1),
        ),
      ),
      throwsA(isA<AppException>()),
    );

    expect(await categories.getByPackage(packageId), hasLength(1));
    expect(await mainCapacity(packageId), 20 * gb);
  });

  test('kategori MAIN tidak dapat dihapus', () async {
    final packageId = await createPackage();
    final main = (await categories.getByPackage(packageId)).single;

    await expectLater(
      categories.delete(main.id!),
      throwsA(isA<AppException>()),
    );

    expect(await categories.getById(main.id!), isNotNull);
    expect(await mainCapacity(packageId), 20 * gb);
  });

  test(
    'siklus tambah, ubah, dan hapus menjaga total kapasitas paket',
    () async {
      final packageId = await createPackage();

      final nightId = await categories.add(
        category(packageId, capacityBytes: 5 * gb),
      );
      expect(await mainCapacity(packageId), 15 * gb);

      final socialId = await categories.add(
        category(
          packageId,
          name: 'Kuota Sosial',
          type: QuotaCategoryType.social,
          capacityBytes: 3 * gb,
        ),
      );
      expect(await mainCapacity(packageId), 12 * gb);

      final night = (await categories.getById(nightId))!;
      await categories.update(night.copyWith(capacityBytes: 7 * gb));

      expect(await mainCapacity(packageId), 10 * gb);

      await categories.delete(socialId);

      expect(await mainCapacity(packageId), 13 * gb);
      expect(
        (await categories.getByPackage(packageId))
            .fold<int>(0, (total, item) => total + item.capacityBytes),
        20 * gb,
      );
    },
  );

  test('kapasitas melebihi sisa MAIN ditolak tanpa mengubah data', () async {
    final packageId = await createPackage();

    await expectLater(
      categories.add(
        category(
          packageId,
          name: 'Terlalu Besar',
          type: QuotaCategoryType.custom,
          capacityBytes: 21 * gb,
        ),
      ),
      throwsA(isA<AppException>()),
    );

    expect(await categories.getByPackage(packageId), hasLength(1));
    expect(await mainCapacity(packageId), 20 * gb);
  });

  test('kategori paket lain tidak tercampur', () async {
    final firstId = await createPackage(name: 'Paket Pertama');
    final secondId = await createPackage(
      name: 'Paket Kedua',
      status: PackageStatus.inactive,
    );

    await categories.add(category(firstId));

    expect(await categories.getByPackage(firstId), hasLength(2));
    expect(await categories.getByPackage(secondId), hasLength(1));
    expect(await mainCapacity(secondId), 20 * gb);
  });

  test(
    'kategori dan kapasitas tetap tersimpan setelah database dibuka ulang',
    () async {
      final packageId = await createPackage();

      await categories.add(category(packageId, capacityBytes: 5 * gb));

      await helper.close();
      await openDatabase();

      final rows = await categories.getByPackage(packageId);

      expect(rows, hasLength(2));
      expect(
        rows
            .singleWhere((item) => item.categoryType == QuotaCategoryType.night)
            .capacityBytes,
        5 * gb,
      );
      expect(await mainCapacity(packageId), 15 * gb);
    },
  );
}
