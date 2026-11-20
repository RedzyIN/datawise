import 'package:datawise/features/package/quota_category_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gb = 1000000000;

  late InMemoryPackageRepository packages;
  late InMemoryQuotaCategoryRepository repository;
  late QuotaCategoryProvider provider;

  setUp(() {
    packages = InMemoryPackageRepository();
    repository = InMemoryQuotaCategoryRepository(packages);
    provider = QuotaCategoryProvider(repository);
  });

  Future<String> createPackage({
    String userId = 'user-1',
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
      createdAt: DateTime.now(),
    );
  }

  test(
    'load memuat kategori MAIN otomatis dengan kapasitas penuh paket',
    () async {
      final packageId = await createPackage();

      await provider.load(packageId);

      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.categories, hasLength(1));
      expect(provider.mainCategory, isNotNull);
      expect(provider.mainCapacityBytes, 20 * gb);
      expect(provider.totalAllocatedBytes, 20 * gb);
      expect(provider.additionalCategories, isEmpty);
    },
  );

  test(
    'menambah kategori mengambil kapasitas dari MAIN tanpa menambah total',
    () async {
      final packageId = await createPackage();
      await provider.load(packageId);

      expect(await provider.add(category(packageId)), isTrue);

      expect(provider.mainCapacityBytes, 15 * gb);
      expect(provider.totalAllocatedBytes, 20 * gb);
      expect(provider.additionalCategories, hasLength(1));

      expect(
        await provider.add(
          category(
            packageId,
            name: 'Kuota Sosial',
            type: QuotaCategoryType.social,
            capacityBytes: 3 * gb,
          ),
        ),
        isTrue,
      );

      expect(provider.mainCapacityBytes, 12 * gb);
      expect(provider.totalAllocatedBytes, 20 * gb);
    },
  );

  test('mengubah kapasitas menjaga total kapasitas paket', () async {
    final packageId = await createPackage();
    await provider.load(packageId);
    await provider.add(category(packageId));
    await provider.add(
      category(
        packageId,
        name: 'Kuota Sosial',
        type: QuotaCategoryType.social,
        capacityBytes: 3 * gb,
      ),
    );

    final night = provider.additionalCategories.singleWhere(
      (item) => item.categoryType == QuotaCategoryType.night,
    );

    expect(
      await provider.update(night.copyWith(capacityBytes: 7 * gb)),
      isTrue,
    );

    expect(provider.mainCapacityBytes, 10 * gb);
    expect(provider.totalAllocatedBytes, 20 * gb);

    final social = provider.additionalCategories.singleWhere(
      (item) => item.categoryType == QuotaCategoryType.social,
    );

    expect(await provider.delete(social.id!), isTrue);

    expect(provider.mainCapacityBytes, 13 * gb);
    expect(provider.totalAllocatedBytes, 20 * gb);
    expect(provider.additionalCategories, hasLength(1));
  });

  test('menolak penambahan kapasitas melebihi sisa kuota MAIN', () async {
    final packageId = await createPackage();
    await provider.load(packageId);
    await provider.add(category(packageId, capacityBytes: 5 * gb));

    expect(
      await provider.add(
        category(
          packageId,
          name: 'Kuota Sosial',
          type: QuotaCategoryType.social,
          capacityBytes: 15 * gb,
        ),
      ),
      isFalse,
    );
    expect(provider.errorMessage, isNotNull);
    expect(provider.mainCapacityBytes, 15 * gb);
    expect(provider.categories, hasLength(2));

    expect(
      await provider.add(
        category(
          packageId,
          name: 'Terlalu Besar',
          type: QuotaCategoryType.custom,
          capacityBytes: 30 * gb,
        ),
      ),
      isFalse,
    );
    expect(provider.totalAllocatedBytes, 20 * gb);
  });

  test('menolak kategori MAIN tambahan', () async {
    final packageId = await createPackage();
    await provider.load(packageId);

    expect(
      await provider.add(
        category(packageId, name: 'MAIN kedua', type: QuotaCategoryType.main),
      ),
      isFalse,
    );
    expect(provider.errorMessage, contains('otomatis'));
    expect(provider.categories, hasLength(1));
  });

  test('menolak penghapusan kategori MAIN', () async {
    final packageId = await createPackage();
    await provider.load(packageId);

    expect(await provider.delete(provider.mainCategory!.id!), isFalse);
    expect(provider.errorMessage, contains('tidak boleh dihapus'));
    expect(provider.mainCategory, isNotNull);
    expect(provider.mainCapacityBytes, 20 * gb);
  });

  test('menolak nama kosong dan kapasitas nol', () async {
    final packageId = await createPackage();
    await provider.load(packageId);

    expect(await provider.add(category(packageId, name: '   ')), isFalse);
    expect(provider.errorMessage, contains('Nama kategori'));

    expect(await provider.add(category(packageId, capacityBytes: 0)), isFalse);
    expect(provider.errorMessage, contains('lebih dari 0'));
    expect(provider.categories, hasLength(1));
  });

  test('kategori dari paket berbeda tidak tercampur', () async {
    final firstId = await createPackage(name: 'Paket Pertama');
    final secondId = await createPackage(
      name: 'Paket Kedua',
      status: PackageStatus.inactive,
    );

    await provider.load(firstId);
    await provider.add(category(firstId));

    await provider.load(secondId);

    expect(provider.categories, hasLength(1));
    expect(provider.mainCapacityBytes, 20 * gb);
    expect(provider.additionalCategories, isEmpty);

    await provider.load(firstId);

    expect(provider.additionalCategories, hasLength(1));
    expect(provider.mainCapacityBytes, 15 * gb);
  });

  test('perubahan kapasitas disimpan kembali ke repository', () async {
    final packageId = await createPackage();
    await provider.load(packageId);
    await provider.add(category(packageId));

    final stored = await repository.getByPackage(packageId);
    final main = stored.singleWhere(
      (item) => item.categoryType == QuotaCategoryType.main,
    );

    expect(main.capacityBytes, 15 * gb);
  });

  test('menolak penambahan kategori dari paket yang berbeda', () async {
    final packageId = await createPackage();
    await provider.load(packageId);

    final otherId = await createPackage(
      name: 'Paket Lain',
      status: PackageStatus.inactive,
    );

    expect(
      await provider.add(
        category(otherId, name: 'Salah Paket', type: QuotaCategoryType.social),
      ),
      isFalse,
    );
    expect(provider.errorMessage, contains('Paket kategori tidak ditemukan'));
    expect(provider.categories, hasLength(1));
    expect(provider.additionalCategories, isEmpty);
  });

  test('tanpa load provider tidak membuat kategori untuk paket lain', () async {
    final freshProvider = QuotaCategoryProvider(repository);

    final otherId = await createPackage(
      name: 'Paket Lain',
      status: PackageStatus.inactive,
    );

    // Tanpa load(paketId), guard packageId tidak aktif, sehingga operasi
    // bergantung pada validasi repository saja.
    final result = await freshProvider.add(
      category(
        otherId,
        name: 'Tanpa Load',
        type: QuotaCategoryType.custom,
        capacityBytes: 1 * gb,
      ),
    );

    // Tanpa mainCategory yang dimuat, penambahan harus gagal.
    expect(result, isFalse);
    expect(freshProvider.errorMessage, isNotNull);
    expect(await repository.getByPackage(otherId), hasLength(1));
  });

  test('state setelah operasi gagal tetap konsisten', () async {
    final packageId = await createPackage();
    await provider.load(packageId);

    expect(
      await provider.add(category(packageId, capacityBytes: 5 * gb)),
      isTrue,
    );
    expect(provider.mainCapacityBytes, 15 * gb);
    expect(provider.totalAllocatedBytes, 20 * gb);

    // Operasi gagal tidak mengubah state.
    final before = provider.mainCapacityBytes;
    expect(
      await provider.add(
        category(packageId, capacityBytes: 30 * gb, name: 'Terlalu Besar'),
      ),
      isFalse,
    );
    expect(provider.mainCapacityBytes, before);
    expect(provider.additionalCategories, hasLength(1));
    expect(provider.errorMessage, isNotNull);

    provider.clearError();
    expect(provider.errorMessage, isNull);
  });

  test('memuat ulang kategori setelah operasi berhasil', () async {
    final packageId = await createPackage();
    await provider.load(packageId);

    expect(
      await provider.add(category(packageId, capacityBytes: 5 * gb)),
      isTrue,
    );
    expect(provider.additionalCategories, hasLength(1));

    await provider.load(packageId);

    expect(provider.additionalCategories, hasLength(1));
    expect(provider.mainCapacityBytes, 15 * gb);
    expect(provider.totalAllocatedBytes, 20 * gb);
    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isFalse);
  });
}
