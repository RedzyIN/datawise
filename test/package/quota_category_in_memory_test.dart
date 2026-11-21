import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

/// Skenario yang sama dengan `quota_category_sqlite_test.dart`, dijalankan pada
/// repository in-memory agar kedua implementasi berperilaku konsisten.
void main() {
  const gb = 1000000000;
  const userId = 'user-1';

  late InMemoryPackageRepository packages;
  late InMemoryQuotaCategoryRepository categories;

  final today = DateTime(2026, 11, 1);
  final defaultStart = DateTime(2026, 11, 1);
  final defaultEnd = DateTime(2026, 12, 1);

  setUp(() {
    packages = InMemoryPackageRepository();
    categories = InMemoryQuotaCategoryRepository(packages);
  });

  DataPackage buildPackage({
    int quotaBytes = 20 * gb,
    DateTime? startDate,
    DateTime? endDate,
    PackageStatus status = PackageStatus.active,
  }) {
    return DataPackage(
      userId: userId,
      packageName: 'Paket Bulanan',
      operatorName: 'Operator',
      advertisedTotalQuotaBytes: quotaBytes,
      startDate: startDate ?? defaultStart,
      endDate: endDate ?? defaultEnd,
      status: status,
      createdAt: today,
      updatedAt: today,
    );
  }

  QuotaCategory buildCategory(
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
      createdAt: today,
    );
  }

  Future<QuotaCategory> mainCategory(String packageId) async {
    final rows = await categories.getByPackage(packageId);

    return rows.singleWhere(
      (item) => item.categoryType == QuotaCategoryType.main,
    );
  }

  Future<int> totalCapacity(String packageId) async {
    final rows = await categories.getByPackage(packageId);

    return rows.fold<int>(0, (total, item) => total + item.capacityBytes);
  }

  test(
    'pembuatan paket membuat satu MAIN sesuai kapasitas dan masa berlaku paket',
    () async {
      final packageId = await packages.add(buildPackage());

      final rows = await categories.getByPackage(packageId);

      expect(rows, hasLength(1));
      expect(rows.single.categoryType, QuotaCategoryType.main);
      expect(rows.single.capacityBytes, 20 * gb);
      expect(rows.single.validFrom, defaultStart);
      expect(rows.single.validUntil, defaultEnd);
    },
  );

  test(
    'penyimpanan paket beserta kategori mengurangi MAIN dan menjaga total',
    () async {
      final packageId = await packages.addWithCategories(
        buildPackage(),
        categories: [
          buildCategory('', capacityBytes: 5 * gb),
          buildCategory(
            '',
            name: 'Kuota Sosial',
            type: QuotaCategoryType.social,
            capacityBytes: 3 * gb,
          ),
        ],
      );

      expect(await categories.getByPackage(packageId), hasLength(3));
      expect((await mainCategory(packageId)).capacityBytes, 12 * gb);
      expect(await totalCapacity(packageId), 20 * gb);
    },
  );

  test('penyimpanan paket dengan kategori gagal bersifat atomik', () async {
    await expectLater(
      packages.addWithCategories(
        buildPackage(),
        categories: [buildCategory('', capacityBytes: 25 * gb)],
      ),
      throwsA(isA<AppException>()),
    );

    expect(await packages.getAll(userId), isEmpty);
    expect(await packages.getActive(userId), isNull);

    final packageId = await packages.addWithCategories(
      buildPackage(),
      categories: [buildCategory('', capacityBytes: 5 * gb)],
    );

    expect(await packages.getAll(userId), hasLength(1));
    expect(await categories.getByPackage(packageId), hasLength(2));
    expect((await mainCategory(packageId)).capacityBytes, 15 * gb);
  });

  test('perubahan tanggal paket memperbarui masa berlaku MAIN', () async {
    final packageId = await packages.add(buildPackage());
    final stored = (await packages.getById(packageId))!;

    await packages.update(
      stored.copyWith(
        startDate: DateTime(2026, 11, 5),
        endDate: DateTime(2027, 1, 15),
      ),
    );

    final main = await mainCategory(packageId);

    expect(main.validFrom, DateTime(2026, 11, 5));
    expect(main.validUntil, DateTime(2027, 1, 15));
    expect(main.capacityBytes, 20 * gb);
  });

  test(
    'masa berlaku kategori tambahan tidak mengubah paket maupun MAIN',
    () async {
      final packageId = await packages.add(buildPackage());
      final categoryId = await categories.add(
        buildCategory(
          packageId,
          validFrom: DateTime(2026, 11, 1),
          validUntil: DateTime(2026, 11, 10),
        ),
      );

      await categories.update(
        (await categories.getById(categoryId))!.copyWith(
          validFrom: DateTime(2026, 11, 2),
          validUntil: DateTime(2026, 11, 20),
        ),
      );

      final storedPackage = (await packages.getById(packageId))!;
      final main = await mainCategory(packageId);
      final updated = (await categories.getById(categoryId))!;

      expect(storedPackage.startDate, defaultStart);
      expect(storedPackage.endDate, defaultEnd);
      expect(main.validFrom, defaultStart);
      expect(main.validUntil, defaultEnd);
      expect(updated.validFrom, DateTime(2026, 11, 2));
      expect(updated.validUntil, DateTime(2026, 11, 20));
    },
  );

  test('menaikkan dan menurunkan total kuota menyesuaikan MAIN', () async {
    final packageId = await packages.add(buildPackage());
    await categories.add(buildCategory(packageId));

    expect((await mainCategory(packageId)).capacityBytes, 15 * gb);

    await packages.update(
      (await packages.getById(packageId))!
          .copyWith(advertisedTotalQuotaBytes: 25 * gb),
    );
    expect((await mainCategory(packageId)).capacityBytes, 20 * gb);

    await packages.update(
      (await packages.getById(packageId))!
          .copyWith(advertisedTotalQuotaBytes: 18 * gb),
    );

    expect((await mainCategory(packageId)).capacityBytes, 13 * gb);
    expect(await totalCapacity(packageId), 18 * gb);
  });

  test('total kuota lebih kecil dari kategori tambahan ditolak', () async {
    final packageId = await packages.add(buildPackage());
    await categories.add(buildCategory(packageId));

    await expectLater(
      packages.update(
        (await packages.getById(packageId))!
            .copyWith(advertisedTotalQuotaBytes: 5 * gb),
      ),
      throwsA(isA<AppException>()),
    );

    expect(
      (await packages.getById(packageId))!.advertisedTotalQuotaBytes,
      20 * gb,
    );
    expect((await mainCategory(packageId)).capacityBytes, 15 * gb);
    expect(await totalCapacity(packageId), 20 * gb);
  });

  test('hanya ada satu MAIN, tidak dapat dihapus dan jenisnya tetap', () async {
    final packageId = await packages.add(buildPackage());

    await expectLater(
      categories.add(
        buildCategory(
          packageId,
          name: 'MAIN kedua',
          type: QuotaCategoryType.main,
        ),
      ),
      throwsA(isA<AppException>()),
    );

    final main = await mainCategory(packageId);

    await expectLater(
      categories.update(main.copyWith(categoryType: QuotaCategoryType.social)),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      categories.delete(main.id!),
      throwsA(isA<AppException>()),
    );

    expect(await categories.getByPackage(packageId), hasLength(1));
    expect((await mainCategory(packageId)).capacityBytes, 20 * gb);
  });

  test(
    'listener gagal setelah MAIN dibuat mengembalikan seluruh data',
    () async {
      packages.addAddListener(
        (package, additional) => throw StateError('gagal setelah MAIN'),
      );

      await expectLater(
        packages.addWithCategories(
          buildPackage(),
          categories: [buildCategory('', capacityBytes: 5 * gb)],
          initialUsedBytes: gb,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await packages.getAll(userId), isEmpty);
      expect(packages.initialUsage, isEmpty);
      expect(categories.items, isEmpty);
    },
  );

  test(
    'listener gagal setelah kategori tambahan dibuat tidak menyisakan kategori',
    () async {
      packages.addAddListener((package, additional) {
        categories.items['leftover'] = buildCategory(
          package.id!,
          name: 'Sisa Parsial',
          type: QuotaCategoryType.custom,
          capacityBytes: gb,
        ).copyWith(id: 'leftover');
        throw StateError('gagal setelah kategori tambahan');
      });

      await expectLater(
        packages.addWithCategories(
          buildPackage(),
          categories: [
            buildCategory('', capacityBytes: 5 * gb),
            buildCategory(
              '',
              name: 'Kuota Sosial',
              type: QuotaCategoryType.social,
              capacityBytes: 3 * gb,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      expect(categories.items, isEmpty);
      expect(await packages.getAll(userId), isEmpty);
    },
  );

  test(
    'paket aktif sebelumnya kembali aktif bila penambahan paket gagal',
    () async {
      final existingId = await packages.add(buildPackage());
      final existingBefore = (await packages.getById(existingId))!;

      expect(existingBefore.status, PackageStatus.active);

      packages.addAddListener(
        (package, additional) => throw StateError('gagal menambah paket'),
      );

      await expectLater(
        packages.addWithCategories(buildPackage()),
        throwsA(isA<StateError>()),
      );

      final existingAfter = (await packages.getById(existingId))!;

      expect(existingAfter.status, PackageStatus.active);
      expect(await packages.getActive(userId), isNotNull);
      expect(await packages.getAll(userId), hasLength(1));
      expect(await totalCapacity(existingId), 20 * gb);
    },
  );

  test('listener update gagal mengembalikan paket dan MAIN', () async {
    final packageId = await packages.addWithCategories(
      buildPackage(),
      categories: [buildCategory('', capacityBytes: 5 * gb)],
    );
    final otherId = await packages.add(
      buildPackage(status: PackageStatus.inactive),
    );
    final before = (await packages.getById(packageId))!;
    final mainBefore = await mainCategory(packageId);

    packages.addUpdateListener(
      (oldPackage, newPackage) => throw StateError('gagal update'),
    );

    await expectLater(
      packages.update(
        before.copyWith(
          advertisedTotalQuotaBytes: 30 * gb,
          startDate: DateTime(2026, 11, 10),
          endDate: DateTime(2027, 2, 1),
          status: PackageStatus.active,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final after = (await packages.getById(packageId))!;
    final mainAfter = await mainCategory(packageId);

    expect(after.advertisedTotalQuotaBytes, 20 * gb);
    expect(after.startDate, before.startDate);
    expect(after.endDate, before.endDate);
    expect(after.status, before.status);
    expect(mainAfter.capacityBytes, mainBefore.capacityBytes);
    expect(mainAfter.validFrom, mainBefore.validFrom);
    expect(mainAfter.validUntil, mainBefore.validUntil);
    expect(await totalCapacity(packageId), 20 * gb);

    // Paket lain tidak ikut berubah statusnya.
    expect((await packages.getById(otherId))!.status, PackageStatus.inactive);
  });

  test('validasi rentang tanggal kategori sama dengan SQLite', () async {
    final packageId = await packages.add(buildPackage());

    await expectLater(
      categories.add(
        buildCategory(
          packageId,
          validFrom: DateTime(2026, 12, 1),
          validUntil: DateTime(2026, 11, 1),
        ),
      ),
      throwsA(isA<AppException>()),
    );

    final categoryId = await categories.add(buildCategory(packageId));

    await expectLater(
      categories.update(
        (await categories.getById(categoryId))!.copyWith(
          validFrom: DateTime(2026, 12, 1),
          validUntil: DateTime(2026, 11, 1),
        ),
      ),
      throwsA(isA<AppException>()),
    );

    expect(await totalCapacity(packageId), 20 * gb);
  });
}
