import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/core/constants.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:datawise/services/data_limit_service.dart';
import 'package:datawise/services/local_notification_service.dart';

class FakeNotificationService implements LocalNotificationService {
  final List<String> bodies = [];
  final List<String> payloads = [];

  @override
  Future<void> showWarning({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    bodies.add(body);
    payloads.add(payload ?? '');
  }
}

PlannerResult plannerWithTarget(double? dailyTargetBytes) {
  return PlannerResult(
    status: PlannerStatus.normal,
    totalBytes: 10 * kBytesPerGB,
    usedBytes: 0,
    remainingBytes: 10 * kBytesPerGB,
    remainingDays: 10,
    dailyTargetBytes: dailyTargetBytes,
    weeklyTargetBytes: null,
    todayUsedBytes: 0,
    usagePercent: 0,
    todayPercentOfTarget: null,
  );
}

void main() {
  late InMemoryPackageRepository packageRepo;
  late InMemoryQuotaCategoryRepository categoryRepo;
  late InMemoryUsageRepository usageRepo;
  late InMemoryDataLimitRepository limitRepo;
  late InMemoryAlertRepository alertRepo;
  late InMemorySettingsRepository settingsRepo;
  late FakeNotificationService notifications;
  late DataLimitService service;
  late DataPackage package;

  const dailyLimit = 100 * kBytesPerMB; // 100 MB
  const userId = 'user-1';

  setUp(() async {
    packageRepo = InMemoryPackageRepository();
    categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);
    limitRepo = InMemoryDataLimitRepository(packageRepo);
    alertRepo = InMemoryAlertRepository(packageRepo);
    settingsRepo = InMemorySettingsRepository();
    notifications = FakeNotificationService();

    service = DataLimitService(
      limitRepo,
      usageRepo,
      alertRepo,
      settingsRepo,
      notifications,
    );

    final now = DateTime.now();
    final id = await packageRepo.add(
      DataPackage(
        userId: userId,
        packageName: 'Paket Uji',
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10 * kBytesPerGB,
        startDate: dateOnly(now),
        endDate: dateOnly(now.add(const Duration(days: 30))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );

    package = (await packageRepo.getById(id))!;
  });

  Future<void> saveLimit({
    int? dailyLimitBytes = dailyLimit,
    int warnAtPercent = 80,
    bool isEnabled = true,
  }) {
    return service.saveDailyLimit(
      DataLimitSetting(
        packageId: package.id!,
        dailyLimitBytes: dailyLimitBytes,
        warnAtPercent: warnAtPercent,
        limitAtPercent: 100,
        isEnabled: isEnabled,
        updatedAt: DateTime.now(),
      ),
    );
  }

  group('DataLimitService - Penyimpanan batas', () {
    test('batas harian tersimpan dan dapat dibaca kembali', () async {
      await saveLimit();

      final saved = await service.getDailyLimit(package.id!);

      expect(saved, isNotNull);
      expect(saved!.dailyLimitBytes, dailyLimit);
      expect(saved.warnAtPercent, 80);
      expect(saved.limitAtPercent, 100);
      expect(saved.isEnabled, true);
    });
  });

  group('DataLimitService - Perhitungan persentase', () {
    test('pemakaian normal di bawah ambang tidak memicu alert', () async {
      await saveLimit();

      final evaluation = await service.evaluate(
        packageId: package.id!,
        usedBytes: 50 * kBytesPerMB,
      );

      expect(evaluation.status, DataLimitStatus.normal);
      expect(evaluation.usagePercent, closeTo(50, 0.001));
      expect(evaluation.alertType, isNull);
    });

    test('ambang 80% memicu peringatan lokal', () async {
      await saveLimit();

      final evaluation = await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 80 * kBytesPerMB,
      );

      expect(evaluation.status, DataLimitStatus.warning);
      expect(evaluation.usagePercent, closeTo(80, 0.001));
      expect(evaluation.alertType, AlertType.daily80);
      expect(notifications.bodies.length, 1);

      final logs = await alertRepo.getByPackage(package.id!);
      expect(logs.length, 1);
      expect(logs.single.alertType, 'DAILY80');
    });

    test('ambang 100% memicu peringatan batas tercapai', () async {
      await saveLimit();

      final evaluation = await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: dailyLimit,
      );

      expect(evaluation.status, DataLimitStatus.reached);
      expect(evaluation.alertType, AlertType.daily100);
      expect(notifications.bodies.length, 1);

      final logs = await alertRepo.getByPackage(package.id!);
      expect(logs.single.alertType, 'DAILY100');
    });

    test('pemakaian melewati batas memakai alert dailyOver', () async {
      await saveLimit();

      final evaluation = await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 110 * kBytesPerMB,
      );

      expect(evaluation.status, DataLimitStatus.exceeded);
      expect(evaluation.alertType, AlertType.dailyOver);
      expect(notifications.bodies.length, 1);
    });
  });

  group('DataLimitService - Deduplikasi', () {
    test('notifikasi sama tidak dikirim berulang pada hari yang sama', () async {
      await saveLimit();

      await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 85 * kBytesPerMB,
      );
      await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 90 * kBytesPerMB,
      );

      expect(notifications.bodies.length, 1);

      final logs = await alertRepo.getByPackage(package.id!);
      expect(logs.length, 1);
    });

    test('ambang 80% dan 100% memiliki dedupe key berbeda', () async {
      await saveLimit();

      await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 85 * kBytesPerMB,
      );
      await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 100 * kBytesPerMB,
      );

      expect(notifications.bodies.length, 2);

      final logs = await alertRepo.getByPackage(package.id!);
      expect(logs.map((log) => log.alertType).toSet(), {
        'DAILY80',
        'DAILY100',
      });
    });
  });

  group('DataLimitService - Sumber batas', () {
    test('memakai target Data Planner bila batas khusus tidak ada', () async {
      final evaluation = await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 85 * kBytesPerMB,
        plannerResult: plannerWithTarget(dailyLimit.toDouble()),
      );

      expect(evaluation.limitBytes, dailyLimit);
      expect(evaluation.status, DataLimitStatus.warning);
      expect(notifications.bodies.length, 1);
    });

    test('batas khusus pengguna menang atas target planner', () async {
      await saveLimit(dailyLimitBytes: 200 * kBytesPerMB);

      final evaluation = await service.evaluate(
        packageId: package.id!,
        usedBytes: 100 * kBytesPerMB,
        plannerResult: plannerWithTarget(dailyLimit.toDouble()),
      );

      expect(evaluation.limitBytes, 200 * kBytesPerMB);
      expect(evaluation.status, DataLimitStatus.normal);
    });

    test('tanpa batas khusus dan tanpa planner tidak ada peringatan', () async {
      final evaluation = await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 50 * kBytesPerMB,
      );

      expect(evaluation.status, DataLimitStatus.noLimit);
      expect(notifications.bodies, isEmpty);
    });

    test('batas nonaktif tidak memicu peringatan', () async {
      await saveLimit(isEnabled: false);

      final evaluation = await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 90 * kBytesPerMB,
      );

      expect(evaluation.status, DataLimitStatus.disabled);
      expect(notifications.bodies, isEmpty);
      expect(await alertRepo.getByPackage(package.id!), isEmpty);
    });
  });

  group('DataLimitService - Pengaturan notifikasi', () {
    test('notifikasi tidak dikirim saat dimatikan di Settings', () async {
      await saveLimit();

      await settingsRepo.upsert(
        UserSetting(
          userId: userId,
          themeMode: 'LIGHT',
          paletteKey: 'BLUE',
          notificationsEnabled: false,
          timezoneId: 'Asia/Jakarta',
          updatedAt: DateTime.now(),
        ),
      );

      final evaluation = await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 95 * kBytesPerMB,
      );

      // Evaluasi tetap berjalan, hanya pengiriman notifikasi yang ditahan.
      expect(evaluation.status, DataLimitStatus.warning);
      expect(notifications.bodies, isEmpty);
      expect(await alertRepo.getByPackage(package.id!), isEmpty);
    });

    test('notifikasi dikirim saat preferensi notifikasi aktif', () async {
      await saveLimit();

      await settingsRepo.upsert(
        UserSetting(
          userId: userId,
          themeMode: 'LIGHT',
          paletteKey: 'BLUE',
          notificationsEnabled: true,
          timezoneId: 'Asia/Jakarta',
          updatedAt: DateTime.now(),
        ),
      );

      await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 95 * kBytesPerMB,
      );

      expect(notifications.bodies.length, 1);
    });
  });

  group('DataLimitService - Pemakaian harian', () {
    Future<String> mainCategoryId() async {
      final categories = await categoryRepo.getByPackage(package.id!);
      return categories
          .firstWhere(
            (category) => category.categoryType == QuotaCategoryType.main,
          )
          .id!;
    }

    Future<void> addRecord({
      required UsageRecordScope scope,
      required UsageSource source,
      required int bytes,
      String? sourceKey,
    }) async {
      final now = DateTime.now();
      final record = UsageRecord(
        packageId: package.id!,
        recordScope: scope,
        appPackageName: scope == UsageRecordScope.appUsage
            ? 'com.example.app'
            : null,
        networkType: NetworkType.mobile,
        periodStartAt: dateOnly(now),
        periodEndAt: now.add(const Duration(seconds: 1)),
        rxBytes: bytes,
        txBytes: 0,
        source: source,
        sourceKey: sourceKey,
        recordedAt: now,
      );

      if (scope == UsageRecordScope.deviceTotal) {
        await usageRepo.upsertRecord(record);
        return;
      }

      final categoryId = await mainCategoryId();

      await usageRepo.upsertRecordWithAllocations(record, (usageRecordId) {
        return [
          UsageAllocation(
            packageId: package.id!,
            usageRecordId: usageRecordId,
            quotaCategoryId: categoryId,
            allocatedBytes: bytes,
            allocationMethod: scope == UsageRecordScope.manualTotal
                ? AllocationMethod.manualUser
                : AllocationMethod.mainFallback,
            createdAt: now,
          ),
        ];
      });
    }

    test('input manual menggantikan data otomatis', () async {
      await addRecord(
        scope: UsageRecordScope.appUsage,
        source: UsageSource.android,
        bytes: 7 * kBytesPerMB,
        sourceKey: 'auto-1',
      );
      await addRecord(
        scope: UsageRecordScope.deviceTotal,
        source: UsageSource.android,
        bytes: 9 * kBytesPerMB,
        sourceKey: 'device-1',
      );
      await addRecord(
        scope: UsageRecordScope.manualTotal,
        source: UsageSource.manual,
        bytes: 5 * kBytesPerMB,
        sourceKey: 'manual-1',
      );

      expect(
        await service.usedBytesOn(package.id!, DateTime.now()),
        5 * kBytesPerMB,
      );
    });

    test('agregat perangkat dipakai sebelum total per aplikasi', () async {
      await addRecord(
        scope: UsageRecordScope.appUsage,
        source: UsageSource.android,
        bytes: 7 * kBytesPerMB,
        sourceKey: 'auto-2',
      );
      await addRecord(
        scope: UsageRecordScope.deviceTotal,
        source: UsageSource.android,
        bytes: 9 * kBytesPerMB,
        sourceKey: 'device-2',
      );

      // PRD 5.4: DEVICE_TOTAL menjadi acuan batas harian bila tersedia;
      // APP_USAGE tidak dijumlahkan dan hanya menjadi cadangan.
      expect(
        await service.usedBytesOn(package.id!, DateTime.now()),
        9 * kBytesPerMB,
      );
    });

    test('total per aplikasi dipakai bila agregat perangkat tidak ada', () async {
      await addRecord(
        scope: UsageRecordScope.appUsage,
        source: UsageSource.android,
        bytes: 7 * kBytesPerMB,
        sourceKey: 'auto-3',
      );

      expect(
        await service.usedBytesOn(package.id!, DateTime.now()),
        7 * kBytesPerMB,
      );
    });
  });
}
