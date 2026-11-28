// Pengujian integrasi: AppUsageSyncService → UsageClassificationService →
// ClassificationEngine → repository.
//
// Test ini sengaja tidak memanggil ClassificationEngine secara langsung.
// Seluruh skenario melewati AppUsageSyncService seperti alur produksi, sehingga
// kegagalan integrasi (aturan database tidak dipakai) akan membuat test gagal.
//
// Setiap skenario dijalankan pada dua backend: repository in-memory dan SQLite
// sungguhan (sqflite_common_ffi), agar kontrak trigger/skema ikut terbukti.
import 'package:datawise/core/db_helper.dart';
import 'package:datawise/features/dashboard/dashboard_provider.dart';
import 'package:datawise/features/usage_breakdown/usage_breakdown_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:datawise/services/app_usage_sync_service.dart';
import 'package:datawise/services/usage/usage_classification_service.dart';
import 'package:datawise/services/usage_breakdown_service.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _userId = 'user-integrasi';
const _gb = 1000000000;
const _mb = 1000000;
const _instagram = 'com.instagram.android';
const _youtube = 'com.google.android.youtube';
const _whatsapp = 'com.whatsapp';

/// Waktu hari ini pada jam tertentu. Dipakai agar aturan rentang waktu dapat
/// diuji tanpa bergantung pada jam saat test dijalankan.
DateTime _todayAt(int hour, int minute) =>
    dateOnly(DateTime.now()).add(Duration(hours: hour, minutes: minute));

int _dayBit(int weekday) => 1 << (weekday - 1);

AppUsageBucket _bucket({
  required int uid,
  required String packageName,
  required String appName,
  required int bytes,
  required DateTime start,
}) => AppUsageBucket(
  uid: uid,
  packageName: packageName,
  appName: appName,
  rxBytes: bytes,
  txBytes: 0,
  start: start,
  end: start.add(const Duration(minutes: 30)),
);

class _FakeUsageService implements UsageService {
  int deviceBytes = 0;
  List<AppUsageBucket> buckets = const [];

  UsageReading _deviceReading(DateTime start, DateTime end) => UsageReading(
    status: UsageReadStatus.ok,
    totalBytes: deviceBytes,
    start: start,
    end: end,
    message: null,
  );

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<bool> openInternetSettings() async => true;

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async =>
      _deviceReading(start, end);

  @override
  Future<AppUsageReading> readAppUsage(DateTime start, DateTime end) async =>
      AppUsageReading(
        status: UsageReadStatus.ok,
        buckets: buckets,
        start: start,
        end: end,
        message: null,
      );

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    final now = DateTime.now();
    return _deviceReading(dateOnly(now), now);
  }
}

class _NoopAlertService implements AlertService {
  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> evaluateAndNotify(
    String userId,
    DataPackage package,
    PlannerResult result,
  ) async {}
}

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

  Future<DataPackage> packageOf(String packageId);
  Future<QuotaCategory> mainOf(String packageId);

  Future<String> addCategory(
    String packageId, {
    required String name,
    QuotaCategoryType type = QuotaCategoryType.custom,
    int capacityBytes = 2 * _gb,
    bool isEnabled = true,
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

  UsageRepository get usage;

  AppUsageSyncService syncService(_FakeUsageService monitor);

  UsageBreakdownProvider provider(_FakeUsageService monitor);

  DashboardProvider dashboard(_FakeUsageService monitor);
}

mixin _BackendScenarioHelpers implements _Backend {
  PackageRepository get packageRepository;
  QuotaCategoryRepository get categoryRepository;
  ClassificationRuleRepository get ruleRepository;

  @override
  Future<String> createPackage({
    String name = 'Paket 20 GB',
    int quotaBytes = 20 * _gb,
    PackageStatus status = PackageStatus.active,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final now = DateTime.now();

    return packageRepository.add(
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
  Future<DataPackage> packageOf(String packageId) async =>
      (await packageRepository.getById(packageId))!;

  @override
  Future<QuotaCategory> mainOf(String packageId) async {
    final rows = await categoryRepository.getByPackage(packageId);
    return rows.singleWhere(
      (item) => item.categoryType == QuotaCategoryType.main,
    );
  }

  @override
  Future<String> addCategory(
    String packageId, {
    required String name,
    QuotaCategoryType type = QuotaCategoryType.custom,
    int capacityBytes = 2 * _gb,
    bool isEnabled = true,
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return categoryRepository.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: name,
        categoryType: type,
        capacityBytes: capacityBytes,
        validFrom: validFrom,
        validUntil: validUntil,
        isEnabled: isEnabled,
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
    return ruleRepository.add(
      ClassificationRule(
        quotaCategoryId: categoryId,
        ruleName: 'Aturan Uji',
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

  UsageClassificationService get classificationService;

  @override
  AppUsageSyncService syncService(_FakeUsageService monitor) =>
      AppUsageSyncService(monitor, usage, classificationService);

  @override
  UsageBreakdownProvider provider(_FakeUsageService monitor) =>
      UsageBreakdownProvider(
        UsageBreakdownService(usage),
        syncService(monitor),
        monitor,
      );

  @override
  DashboardProvider dashboard(_FakeUsageService monitor) => DashboardProvider(
    packageRepository,
    usage,
    monitor,
    _NoopAlertService(),
    categoryRepo: categoryRepository,
    syncService: syncService(monitor),
  );
}

class _InMemoryBackend with _BackendScenarioHelpers {
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
  UsageRepository get usage => usageRepo;

  @override
  InMemoryPackageRepository get packageRepository => packages;

  @override
  InMemoryQuotaCategoryRepository get categoryRepository => categories;

  @override
  InMemoryClassificationRuleRepository get ruleRepository => rules;

  @override
  UsageClassificationService get classificationService =>
      UsageClassificationService(
        ruleRepository: rules,
        categoryRepository: categories,
        usageRepository: usageRepo,
      );
}

class _SqliteBackend with _BackendScenarioHelpers {
  static const _path = 'datawise_app_usage_sync_classification_test.db';

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
    final now = DateTime.now().toIso8601String();

    await db.insert('users', {
      'id': _userId,
      'display_name': 'Pengguna Integrasi',
      'email': 'integrasi@example.com',
      'created_at': now,
      'updated_at': now,
    });
  }

  @override
  Future<void> tearDown() => helper.close();

  @override
  UsageRepository get usage => usageRepo;

  @override
  SqlitePackageRepository get packageRepository => packages;

  @override
  SqliteQuotaCategoryRepository get categoryRepository => categories;

  @override
  SqliteClassificationRuleRepository get ruleRepository => rules;

  @override
  UsageClassificationService get classificationService =>
      UsageClassificationService(
        ruleRepository: rules,
        categoryRepository: categories,
        usageRepository: usageRepo,
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

    // Setiap record APP_USAGE harus punya tepat satu alokasi.
    Future<UsageAllocation> allocationOf(
      String packageId,
      String appPackageName,
    ) async {
      final records = await backend.usage.getRecords(packageId);
      final record = records.singleWhere(
        (item) => item.appPackageName == appPackageName,
      );
      final allocations = await backend.usage.getAllocations(record.id!);
      expect(allocations, hasLength(1));
      return allocations.single;
    }

    test('aturan tersimpan di database menentukan kategori alokasi', () async {
      final packageId = await backend.createPackage();
      final socialId = await backend.addCategory(
        packageId,
        name: 'Kuota Sosial',
        type: QuotaCategoryType.social,
      );
      final ruleId = await backend.addRule(
        packageId: packageId,
        categoryId: socialId,
        appPackageName: _instagram,
        startMinute: 0,
        endMinute: 1440,
      );

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 3 * _mb,
            start: _todayAt(10, 0),
          ),
          _bucket(
            uid: 102,
            packageName: _youtube,
            appName: 'YouTube',
            bytes: 4 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      final result = await backend
          .syncService(monitor)
          .syncToday(await backend.packageOf(packageId));

      expect(result.savedAppRecords, 2);
      expect(result.skippedAppRecords, 0);

      final instagram = await allocationOf(packageId, _instagram);

      expect(instagram.allocationMethod, AllocationMethod.autoRule);
      expect(instagram.quotaCategoryId, socialId);
      expect(instagram.classificationRuleId, ruleId);
      expect(instagram.allocatedBytes, 3 * _mb);

      // Aplikasi tanpa aturan tetap memakai MAIN fallback pada sinkronisasi
      // yang sama, jadi dua jalur klasifikasi hidup berdampingan.
      final main = await backend.mainOf(packageId);
      final youtube = await allocationOf(packageId, _youtube);

      expect(youtube.allocationMethod, AllocationMethod.mainFallback);
      expect(youtube.quotaCategoryId, main.id);
      expect(youtube.classificationRuleId, isNull);
    });

    test('tanpa aturan yang cocok memakai MAIN fallback', () async {
      final packageId = await backend.createPackage();
      final main = await backend.mainOf(packageId);

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 2 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      final result = await backend
          .syncService(monitor)
          .syncToday(await backend.packageOf(packageId));

      expect(result.savedAppRecords, 1);

      final allocation = await allocationOf(packageId, _instagram);

      expect(allocation.allocationMethod, AllocationMethod.mainFallback);
      expect(allocation.quotaCategoryId, main.id);
      expect(allocation.classificationRuleId, isNull);
    });

    test('aturan nonaktif tidak digunakan', () async {
      final packageId = await backend.createPackage();
      final socialId = await backend.addCategory(
        packageId,
        name: 'Kuota Sosial',
        type: QuotaCategoryType.social,
      );

      await backend.addRule(
        packageId: packageId,
        categoryId: socialId,
        appPackageName: _instagram,
        startMinute: 0,
        endMinute: 1440,
        isEnabled: false,
      );

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 2 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      await backend
          .syncService(monitor)
          .syncToday(await backend.packageOf(packageId));

      final allocation = await allocationOf(packageId, _instagram);
      final main = await backend.mainOf(packageId);

      expect(allocation.allocationMethod, AllocationMethod.mainFallback);
      expect(allocation.quotaCategoryId, main.id);
    });

    test('kategori aturan yang sudah kedaluwarsa tidak dipakai', () async {
      final packageId = await backend.createPackage();
      final expiredId = await backend.addCategory(
        packageId,
        name: 'Kuota Sosial Lama',
        type: QuotaCategoryType.social,
        validUntil: dateOnly(DateTime.now()).subtract(const Duration(days: 1)),
      );

      await backend.addRule(
        packageId: packageId,
        categoryId: expiredId,
        appPackageName: _instagram,
        startMinute: 0,
        endMinute: 1440,
      );

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 2 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      final result = await backend
          .syncService(monitor)
          .syncToday(await backend.packageOf(packageId));

      // Catatan tetap tersimpan, hanya klasifikasinya yang UNCLASSIFIED.
      expect(result.savedAppRecords, 1);

      final allocation = await allocationOf(packageId, _instagram);

      expect(allocation.allocationMethod, AllocationMethod.unclassified);
      expect(allocation.quotaCategoryId, isNull);
      expect(allocation.allocatedBytes, 2 * _mb);
    });

    test('kategori aturan yang dinonaktifkan tidak dipakai', () async {
      final packageId = await backend.createPackage();
      final disabledId = await backend.addCategory(
        packageId,
        name: 'Kuota Sosial Nonaktif',
        type: QuotaCategoryType.social,
        isEnabled: false,
      );

      await backend.addRule(
        packageId: packageId,
        categoryId: disabledId,
        appPackageName: _instagram,
        startMinute: 0,
        endMinute: 1440,
      );

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 2 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      await backend
          .syncService(monitor)
          .syncToday(await backend.packageOf(packageId));

      final allocation = await allocationOf(packageId, _instagram);

      expect(allocation.allocationMethod, AllocationMethod.unclassified);
      expect(allocation.quotaCategoryId, isNull);
    });

    test(
      'kategori MAIN yang kedaluwarsa tidak dipakai sebagai fallback',
      () async {
        final now = DateTime.now();
        final packageId = await backend.createPackage(
          status: PackageStatus.inactive,
          startDate: dateOnly(now).subtract(const Duration(days: 40)),
          endDate: dateOnly(now).subtract(const Duration(days: 10)),
        );

        final monitor = _FakeUsageService()
          ..buckets = [
            _bucket(
              uid: 101,
              packageName: _instagram,
              appName: 'Instagram',
              bytes: 2 * _mb,
              start: _todayAt(10, 0),
            ),
          ];

        final result = await backend
            .syncService(monitor)
            .syncToday(await backend.packageOf(packageId));

        expect(result.savedAppRecords, 1);

        final allocation = await allocationOf(packageId, _instagram);

        // MAIN kedaluwarsa tidak boleh dipakai; kontraknya UNCLASSIFIED.
        expect(allocation.allocationMethod, AllocationMethod.unclassified);
        expect(allocation.quotaCategoryId, isNull);
      },
    );

    test('sinkronisasi berulang tidak menggandakan alokasi', () async {
      final packageId = await backend.createPackage();
      final socialId = await backend.addCategory(
        packageId,
        name: 'Kuota Sosial',
        type: QuotaCategoryType.social,
      );

      await backend.addRule(
        packageId: packageId,
        categoryId: socialId,
        appPackageName: _instagram,
        startMinute: 0,
        endMinute: 1440,
      );

      final package = await backend.packageOf(packageId);
      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 2 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      await backend.syncService(monitor).syncToday(package);

      // Bucket yang sama dibaca ulang dengan angka lebih besar.
      monitor.buckets = [
        _bucket(
          uid: 101,
          packageName: _instagram,
          appName: 'Instagram',
          bytes: 5 * _mb,
          start: _todayAt(10, 0),
        ),
      ];

      await backend.syncService(monitor).syncToday(package);

      final records = await backend.usage.getRecords(packageId);

      expect(records, hasLength(1));
      expect(records.single.totalBytes, 5 * _mb);

      final allocations = await backend.usage.getAllocations(
        records.single.id!,
      );

      expect(allocations, hasLength(1));
      expect(allocations.single.allocatedBytes, 5 * _mb);
      expect(allocations.single.quotaCategoryId, socialId);
      expect(allocations.single.allocationMethod, AllocationMethod.autoRule);
    });

    test('prioritas, wildcard, dan aturan spesifik aplikasi', () async {
      final packageId = await backend.createPackage();
      final socialId = await backend.addCategory(
        packageId,
        name: 'Kuota Sosial',
        type: QuotaCategoryType.social,
      );
      final appSpecificId = await backend.addCategory(
        packageId,
        name: 'Kuota YouTube',
        type: QuotaCategoryType.appSpecific,
      );
      final customId = await backend.addCategory(
        packageId,
        name: 'Kuota Prioritas',
        type: QuotaCategoryType.custom,
      );

      // Wildcard (tanpa nama paket) berlaku untuk semua aplikasi.
      await backend.addRule(
        packageId: packageId,
        categoryId: socialId,
        startMinute: 0,
        endMinute: 1440,
      );
      // Prioritas sama: aturan spesifik mengalahkan wildcard.
      await backend.addRule(
        packageId: packageId,
        categoryId: appSpecificId,
        appPackageName: _youtube,
        startMinute: 0,
        endMinute: 1440,
      );
      // Prioritas lebih tinggi mengalahkan aturan spesifik lain.
      await backend.addRule(
        packageId: packageId,
        categoryId: customId,
        appPackageName: _instagram,
        startMinute: 0,
        endMinute: 1440,
        priority: 5,
      );

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 1 * _mb,
            start: _todayAt(10, 0),
          ),
          _bucket(
            uid: 102,
            packageName: _youtube,
            appName: 'YouTube',
            bytes: 1 * _mb,
            start: _todayAt(10, 0),
          ),
          _bucket(
            uid: 103,
            packageName: _whatsapp,
            appName: 'WhatsApp',
            bytes: 1 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      await backend
          .syncService(monitor)
          .syncToday(await backend.packageOf(packageId));

      expect(
        (await allocationOf(packageId, _instagram)).quotaCategoryId,
        customId,
      );
      expect(
        (await allocationOf(packageId, _youtube)).quotaCategoryId,
        appSpecificId,
      );
      expect(
        (await allocationOf(packageId, _whatsapp)).quotaCategoryId,
        socialId,
      );
    });

    test('rentang waktu dan aturan lintas tengah malam', () async {
      final packageId = await backend.createPackage();
      final socialId = await backend.addCategory(
        packageId,
        name: 'Kuota Malam',
        type: QuotaCategoryType.social,
      );

      // 22:00 - 01:00 melewati tengah malam.
      await backend.addRule(
        packageId: packageId,
        categoryId: socialId,
        startMinute: 22 * 60,
        endMinute: 60,
      );

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 2 * _mb,
            start: _todayAt(23, 30),
          ),
          _bucket(
            uid: 102,
            packageName: _youtube,
            appName: 'YouTube',
            bytes: 2 * _mb,
            start: _todayAt(12, 0),
          ),
        ];

      final result = await backend
          .syncService(monitor)
          .syncToday(await backend.packageOf(packageId));

      expect(result.savedAppRecords, 2);

      final insideWindow = await allocationOf(packageId, _instagram);
      final outsideWindow = await allocationOf(packageId, _youtube);
      final main = await backend.mainOf(packageId);

      expect(insideWindow.allocationMethod, AllocationMethod.autoRule);
      expect(insideWindow.quotaCategoryId, socialId);

      expect(outsideWindow.allocationMethod, AllocationMethod.mainFallback);
      expect(outsideWindow.quotaCategoryId, main.id);
    });

    test('hari aktif aturan menentukan kecocokan', () async {
      final packageId = await backend.createPackage();
      final socialId = await backend.addCategory(
        packageId,
        name: 'Kuota Sosial',
        type: QuotaCategoryType.social,
      );
      final customId = await backend.addCategory(
        packageId,
        name: 'Kuota Hari Ini',
        type: QuotaCategoryType.custom,
      );

      final today = DateTime.now().weekday;

      await backend.addRule(
        packageId: packageId,
        categoryId: socialId,
        appPackageName: _instagram,
        startMinute: 0,
        endMinute: 1440,
        daysOfWeekMask: _dayBit(today),
      );
      await backend.addRule(
        packageId: packageId,
        categoryId: customId,
        appPackageName: _youtube,
        startMinute: 0,
        endMinute: 1440,
        daysOfWeekMask: 127 & ~_dayBit(today),
      );

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 1 * _mb,
            start: _todayAt(10, 0),
          ),
          _bucket(
            uid: 102,
            packageName: _youtube,
            appName: 'YouTube',
            bytes: 1 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      await backend
          .syncService(monitor)
          .syncToday(await backend.packageOf(packageId));

      expect(
        (await allocationOf(packageId, _instagram)).quotaCategoryId,
        socialId,
      );

      final youtube = await allocationOf(packageId, _youtube);
      final main = await backend.mainOf(packageId);

      expect(youtube.allocationMethod, AllocationMethod.mainFallback);
      expect(youtube.quotaCategoryId, main.id);
    });

    test(
      'UsageBreakdownProvider menyinkronkan lewat klasifikasi tersimpan',
      () async {
        final packageId = await backend.createPackage();
        final socialId = await backend.addCategory(
          packageId,
          name: 'Kuota Sosial',
          type: QuotaCategoryType.social,
        );

        await backend.addRule(
          packageId: packageId,
          categoryId: socialId,
          appPackageName: _instagram,
          startMinute: 0,
          endMinute: 1440,
        );

        final monitor = _FakeUsageService()
          ..buckets = [
            _bucket(
              uid: 101,
              packageName: _instagram,
              appName: 'Instagram',
              bytes: 3 * _mb,
              start: _todayAt(10, 0),
            ),
          ];

        final provider = backend.provider(monitor);
        addTearDown(provider.dispose);

        await provider.load(await backend.packageOf(packageId));

        expect(provider.errorMessage, isNull);
        expect(provider.breakdown?.apps.single.totalBytes, 3 * _mb);

        final allocation = await allocationOf(packageId, _instagram);

        expect(allocation.allocationMethod, AllocationMethod.autoRule);
        expect(allocation.quotaCategoryId, socialId);
      },
    );

    // Skenario 1, 2, 3, dan 5: klasifikasi, breakdown, dan dashboard memakai
    // record APP_USAGE yang sama, sementara total memakai DEVICE_TOTAL.
    test(
      'Dashboard memakai alokasi APP_USAGE tanpa menjumlahkan DEVICE_TOTAL',
      () async {
        final packageId = await backend.createPackage();
        final main = await backend.mainOf(packageId);
        final socialId = await backend.addCategory(
          packageId,
          name: 'Kuota Sosial',
          type: QuotaCategoryType.social,
        );

        await backend.addRule(
          packageId: packageId,
          categoryId: socialId,
          appPackageName: _instagram,
          startMinute: 0,
          endMinute: 1440,
        );

        final monitor = _FakeUsageService()
          ..deviceBytes = 100 * _mb
          ..buckets = [
            _bucket(
              uid: 101,
              packageName: _instagram,
              appName: 'Instagram',
              bytes: 20 * _mb,
              start: _todayAt(10, 0),
            ),
            _bucket(
              uid: 102,
              packageName: _youtube,
              appName: 'YouTube',
              bytes: 30 * _mb,
              start: _todayAt(10, 0),
            ),
          ];

        final dashboard = backend.dashboard(monitor);
        addTearDown(dashboard.dispose);

        await dashboard.refresh(_userId);

        expect(dashboard.loadState, DashboardLoad.ready);

        // Total dari DEVICE_TOTAL, bukan DEVICE_TOTAL + APP_USAGE.
        expect(dashboard.totalUsedBytes, 100 * _mb);
        expect(dashboard.dailyUsage[dateOnly(DateTime.now())], 100 * _mb);

        final social = dashboard.categoryUsage.singleWhere(
          (item) => item.category.id == socialId,
        );
        final mainUsage = dashboard.categoryUsage.singleWhere(
          (item) => item.category.id == main.id,
        );

        // AUTO_RULE Instagram masuk SOCIAL, MAIN fallback YouTube masuk MAIN.
        expect(social.usedBytes, 20 * _mb);
        expect(mainUsage.usedBytes, 30 * _mb);
        expect(
          dashboard.categoryUsage.fold<int>(
            0,
            (sum, item) => sum + item.usedBytes,
          ),
          50 * _mb,
        );

        // Selisih perangkat bukan UNCLASSIFIED aplikasi.
        expect(dashboard.unclassifiedAppBytes, 0);
        expect(dashboard.unmappedDeviceBytes, 50 * _mb);
        expect(dashboard.unclassifiedBytes, 50 * _mb);

        // Fitri membaca record APP_USAGE yang sama dengan Dashboard.
        final breakdown = await UsageBreakdownService(backend.usage)
            .build(packageId: packageId);

        expect(breakdown.appTotalBytes, 50 * _mb);
        expect(
          breakdown.apps.map((item) => item.appPackageName),
          containsAll(<String>[_instagram, _youtube]),
        );
        expect(breakdown.deviceTotalBytes, 100 * _mb);
        expect(breakdown.differenceBytes, 50 * _mb);
      },
    );

    // Skenario 4: kategori tidak valid tidak boleh jatuh ke MAIN.
    test('UNCLASSIFIED APP_USAGE tidak dibebankan ke MAIN', () async {
      final packageId = await backend.createPackage();
      final main = await backend.mainOf(packageId);
      final expiredId = await backend.addCategory(
        packageId,
        name: 'Kuota Sosial Lama',
        type: QuotaCategoryType.social,
        validUntil: dateOnly(DateTime.now()).subtract(const Duration(days: 1)),
      );

      await backend.addRule(
        packageId: packageId,
        categoryId: expiredId,
        appPackageName: _instagram,
        startMinute: 0,
        endMinute: 1440,
      );

      final monitor = _FakeUsageService()
        ..buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 4 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

      final dashboard = backend.dashboard(monitor);
      addTearDown(dashboard.dispose);

      await dashboard.refresh(_userId);

      expect(dashboard.totalUsedBytes, 4 * _mb);
      expect(dashboard.unclassifiedAppBytes, 4 * _mb);
      expect(dashboard.unmappedDeviceBytes, 0);

      final mainUsage = dashboard.categoryUsage.singleWhere(
        (item) => item.category.id == main.id,
      );

      expect(mainUsage.usedBytes, 0);
      expect(
        dashboard.categoryUsage.fold<int>(
          0,
          (sum, item) => sum + item.usedBytes,
        ),
        0,
      );
    });

    // Skenario 6: sinkronisasi berulang dari Dashboard dan Breakdown.
    test(
      'sinkronisasi Dashboard dan Breakdown tidak menggandakan data',
      () async {
        final packageId = await backend.createPackage();
        final socialId = await backend.addCategory(
          packageId,
          name: 'Kuota Sosial',
          type: QuotaCategoryType.social,
        );

        await backend.addRule(
          packageId: packageId,
          categoryId: socialId,
          appPackageName: _instagram,
          startMinute: 0,
          endMinute: 1440,
        );

        final monitor = _FakeUsageService()
          ..deviceBytes = 100 * _mb
          ..buckets = [
            _bucket(
              uid: 101,
              packageName: _instagram,
              appName: 'Instagram',
              bytes: 20 * _mb,
              start: _todayAt(10, 0),
            ),
          ];

        final dashboard = backend.dashboard(monitor);
        addTearDown(dashboard.dispose);

        await dashboard.refresh(_userId);

        final breakdownProvider = backend.provider(monitor);
        addTearDown(breakdownProvider.dispose);

        await breakdownProvider.load(await backend.packageOf(packageId));

        // Bucket yang sama dibaca ulang dengan angka lebih besar.
        monitor.deviceBytes = 110 * _mb;
        monitor.buckets = [
          _bucket(
            uid: 101,
            packageName: _instagram,
            appName: 'Instagram',
            bytes: 25 * _mb,
            start: _todayAt(10, 0),
          ),
        ];

        await dashboard.refresh(_userId);

        final records = await backend.usage.getRecords(packageId);
        final appRecords = records
            .where((record) => record.recordScope == UsageRecordScope.appUsage)
            .toList();
        final deviceRecords = records
            .where(
              (record) => record.recordScope == UsageRecordScope.deviceTotal,
            )
            .toList();

        expect(appRecords, hasLength(1));
        expect(deviceRecords, hasLength(1));
        expect(appRecords.single.totalBytes, 25 * _mb);

        final allocations = await backend.usage.getAllocations(
          appRecords.single.id!,
        );

        expect(allocations, hasLength(1));
        expect(allocations.single.allocatedBytes, 25 * _mb);
        expect(allocations.single.quotaCategoryId, socialId);

        expect(dashboard.totalUsedBytes, 110 * _mb);
        expect(
          dashboard.categoryUsage
              .singleWhere((item) => item.category.id == socialId)
              .usedBytes,
          25 * _mb,
        );
        expect(dashboard.unmappedDeviceBytes, 85 * _mb);
      },
    );

    // Skenario 7: mode manual tetap prioritas dan tidak dijumlahkan dengan
    // alokasi APP_USAGE pada tanggal yang sama.
    test(
      'MANUAL_TOTAL tetap prioritas tanpa menghitung ganda kategori',
      () async {
        final packageId = await backend.createPackage();
        final main = await backend.mainOf(packageId);
        final socialId = await backend.addCategory(
          packageId,
          name: 'Kuota Sosial',
          type: QuotaCategoryType.social,
        );

        await backend.addRule(
          packageId: packageId,
          categoryId: socialId,
          appPackageName: _instagram,
          startMinute: 0,
          endMinute: 1440,
        );

        final now = DateTime.now();
        final start = dateOnly(now);

        await backend.usage.upsertRecordWithAllocations(
          UsageRecord(
            packageId: packageId,
            recordScope: UsageRecordScope.manualTotal,
            networkType: NetworkType.mobile,
            periodStartAt: start,
            periodEndAt: now.isAfter(start)
                ? now
                : start.add(const Duration(seconds: 1)),
            rxBytes: 80 * _mb,
            txBytes: 0,
            source: UsageSource.manual,
            sourceKey: 'manual_${packageId}_${start.millisecondsSinceEpoch}',
            recordedAt: now,
          ),
          (usageRecordId) => [
            UsageAllocation(
              packageId: packageId,
              usageRecordId: usageRecordId,
              quotaCategoryId: main.id,
              allocatedBytes: 80 * _mb,
              allocationMethod: AllocationMethod.manualUser,
              createdAt: now,
            ),
          ],
        );

        final monitor = _FakeUsageService()
          ..deviceBytes = 100 * _mb
          ..buckets = [
            _bucket(
              uid: 101,
              packageName: _instagram,
              appName: 'Instagram',
              bytes: 20 * _mb,
              start: _todayAt(10, 0),
            ),
          ];

        final dashboard = backend.dashboard(monitor);
        addTearDown(dashboard.dispose);

        await dashboard.refresh(_userId);

        // MANUAL_TOTAL menang atas DEVICE_TOTAL dan APP_USAGE pada hari itu.
        expect(dashboard.totalUsedBytes, 80 * _mb);
        expect(
          dashboard.categoryUsage
              .singleWhere((item) => item.category.id == main.id)
              .usedBytes,
          80 * _mb,
        );
        expect(
          dashboard.categoryUsage
              .singleWhere((item) => item.category.id == socialId)
              .usedBytes,
          0,
        );
        expect(dashboard.unclassifiedAppBytes, 0);
        expect(dashboard.unmappedDeviceBytes, 0);
        expect(dashboard.unclassifiedBytes, 0);
      },
    );
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
