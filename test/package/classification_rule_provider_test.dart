import 'package:datawise/features/package/classification_rule_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gb = 1000000000;

  late InMemoryPackageRepository packages;
  late InMemoryQuotaCategoryRepository categories;
  late InMemoryClassificationRuleRepository rules;
  late ClassificationRuleProvider provider;

  setUp(() {
    packages = InMemoryPackageRepository();
    categories = InMemoryQuotaCategoryRepository(packages);
    rules = InMemoryClassificationRuleRepository(packages, categories);
    provider = ClassificationRuleProvider(rules);
  });

  Future<String> createPackage({String name = 'Paket 20 GB'}) {
    final now = DateTime.now();

    return packages.add(
      DataPackage(
        userId: 'user-1',
        packageName: name,
        operatorName: 'Operator',
        advertisedTotalQuotaBytes: 20 * gb,
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 30)),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Kategori utama dibuat otomatis bersama paket.
  Future<String> mainCategoryId(String packageId) async {
    final stored = await categories.getByPackage(packageId);
    return stored
        .singleWhere((item) => item.categoryType == QuotaCategoryType.main)
        .id!;
  }

  ClassificationRule rule(
    String categoryId, {
    String name = 'WhatsApp Malam',
    String? appPackageName = 'com.whatsapp',
    int? startMinute,
    int? endMinute,
    int daysOfWeekMask = 127,
    int priority = 10,
    bool isEnabled = true,
  }) {
    return ClassificationRule(
      quotaCategoryId: categoryId,
      ruleName: name,
      appPackageName: appPackageName,
      startMinute: startMinute,
      endMinute: endMinute,
      daysOfWeekMask: daysOfWeekMask,
      priority: priority,
      isEnabled: isEnabled,
      createdAt: DateTime.now(),
    );
  }

  test('load paket tanpa aturan menghasilkan daftar kosong', () async {
    final packageId = await createPackage();

    await provider.load(packageId);

    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.rules, isEmpty);
  });

  test('menambah aturan menyimpan ke repository dan memuat ulang', () async {
    final packageId = await createPackage();
    final categoryId = await mainCategoryId(packageId);
    await provider.load(packageId);

    expect(await provider.add(rule(categoryId)), isTrue);

    expect(provider.errorMessage, isNull);
    expect(provider.rules, hasLength(1));
    expect(provider.rules.single.ruleName, 'WhatsApp Malam');
    expect(await rules.getByPackage(packageId), hasLength(1));
  });

  test('aturan diurutkan berdasarkan prioritas tertinggi', () async {
    final packageId = await createPackage();
    final categoryId = await mainCategoryId(packageId);
    await provider.load(packageId);

    await provider.add(rule(categoryId, name: 'Rendah', priority: 1));
    await provider.add(rule(categoryId, name: 'Tinggi', priority: 50));
    await provider.add(rule(categoryId, name: 'Sedang', priority: 10));

    expect(provider.rules.map((item) => item.ruleName), [
      'Tinggi',
      'Sedang',
      'Rendah',
    ]);
  });

  test('mengubah aturan memperbarui data tersimpan', () async {
    final packageId = await createPackage();
    final categoryId = await mainCategoryId(packageId);
    await provider.load(packageId);
    await provider.add(rule(categoryId));

    final stored = provider.rules.single;

    expect(
      await provider.update(
        ClassificationRule(
          id: stored.id,
          quotaCategoryId: stored.quotaCategoryId,
          ruleName: 'WhatsApp Siang',
          appPackageName: stored.appPackageName,
          startMinute: 480,
          endMinute: 1020,
          daysOfWeekMask: stored.daysOfWeekMask,
          priority: stored.priority,
          isEnabled: stored.isEnabled,
          createdAt: stored.createdAt,
        ),
      ),
      isTrue,
    );

    expect(provider.rules.single.ruleName, 'WhatsApp Siang');
    expect(provider.rules.single.startMinute, 480);
    expect(provider.rules.single.endMinute, 1020);
  });

  test('menonaktifkan aturan hanya mengubah status', () async {
    final packageId = await createPackage();
    final categoryId = await mainCategoryId(packageId);
    await provider.load(packageId);
    await provider.add(rule(categoryId));

    final stored = provider.rules.single;

    expect(await provider.setEnabled(stored, false), isTrue);

    expect(provider.rules.single.isEnabled, isFalse);
    expect(provider.rules.single.ruleName, stored.ruleName);
    expect(provider.rules.single.priority, stored.priority);
  });

  test('menghapus aturan menghilangkannya dari daftar', () async {
    final packageId = await createPackage();
    final categoryId = await mainCategoryId(packageId);
    await provider.load(packageId);
    await provider.add(rule(categoryId));

    expect(await provider.delete(provider.rules.single.id!), isTrue);
    expect(provider.rules, isEmpty);
    expect(await rules.getByPackage(packageId), isEmpty);
  });

  test(
    'aturan tidak valid ditolak repository dan pesannya diteruskan',
    () async {
      final packageId = await createPackage();
      final categoryId = await mainCategoryId(packageId);
      await provider.load(packageId);

      expect(await provider.add(rule(categoryId, name: '   ')), isFalse);
      expect(provider.errorMessage, isNotNull);
      expect(provider.rules, isEmpty);

      // Hanya salah satu jam diisi juga tidak valid.
      expect(await provider.add(rule(categoryId, startMinute: 120)), isFalse);
      expect(provider.errorMessage, isNotNull);
      expect(provider.rules, isEmpty);

      // Prioritas negatif ditolak.
      expect(await provider.add(rule(categoryId, priority: -1)), isFalse);
      expect(provider.errorMessage, isNotNull);
    },
  );

  test('aturan paket lain tidak tercampur', () async {
    final firstId = await createPackage(name: 'Paket Pertama');
    final secondId = await createPackage(name: 'Paket Kedua');

    await provider.load(firstId);
    await provider.add(rule(await mainCategoryId(firstId)));

    await provider.load(secondId);

    expect(provider.rules, isEmpty);
    expect(provider.errorMessage, isNull);

    await provider.load(firstId);

    expect(provider.rules, hasLength(1));
  });

  test('clearError mengosongkan pesan gagal', () async {
    final packageId = await createPackage();
    final categoryId = await mainCategoryId(packageId);
    await provider.load(packageId);
    await provider.add(rule(categoryId, name: ''));

    expect(provider.errorMessage, isNotNull);

    provider.clearError();

    expect(provider.errorMessage, isNull);
  });
}
