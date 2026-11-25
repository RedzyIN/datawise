import 'package:datawise/core/constants.dart';
import 'package:datawise/features/data_limit/data_limit_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:datawise/services/alert_dedupe.dart';
import 'package:datawise/services/dashboard_data_limit_calculator.dart';
import 'package:datawise/services/data_limit_background_service.dart';
import 'package:datawise/services/data_limit_service.dart';
import 'package:datawise/services/local_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNotifications implements LocalNotificationService {
  final List<String> bodies = [];
  final List<int> ids = [];
  bool deliver = true;

  @override
  Future<bool> init() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async => true;

  @override
  Future<bool> showWarning({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!deliver) return false;

    bodies.add(body);
    ids.add(id);
    return true;
  }
}

PlannerResult _planner({
  double? dailyTarget = 100000000,
  PlannerStatus status = PlannerStatus.normal,
  int remainingDays = 10,
}) {
  return PlannerResult(
    status: status,
    totalBytes: 10 * kBytesPerGB,
    usedBytes: 0,
    remainingBytes: 10 * kBytesPerGB,
    remainingDays: remainingDays,
    dailyTargetBytes: dailyTarget,
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
  late _FakeNotifications notifications;
  late DataLimitService service;
  late DataPackage package;

  const userId = 'user-1';
  const hundredMb = 100 * kBytesPerMB;

  DataPackage newPackage({
    String name = 'Paket Uji',
    bool active = true,
    int startOffsetDays = 0,
  }) {
    final now = DateTime.now();

    return DataPackage(
      userId: userId,
      packageName: name,
      operatorName: 'Telkomsel',
      advertisedTotalQuotaBytes: 10 * kBytesPerGB,
      startDate: dateOnly(now.add(Duration(days: startOffsetDays))),
      endDate: dateOnly(now.add(const Duration(days: 30))),
      status: active ? PackageStatus.active : PackageStatus.inactive,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> saveLimit(
    String packageId, {
    int? dailyLimitBytes = hundredMb,
    bool isEnabled = true,
  }) {
    return service.saveDailyLimit(
      DataLimitSetting(
        packageId: packageId,
        dailyLimitBytes: dailyLimitBytes,
        warnAtPercent: 80,
        limitAtPercent: 100,
        isEnabled: isEnabled,
        updatedAt: DateTime.now(),
      ),
    );
  }

  setUp(() async {
    packageRepo = InMemoryPackageRepository();
    categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo);
    limitRepo = InMemoryDataLimitRepository(packageRepo);
    alertRepo = InMemoryAlertRepository(packageRepo);
    settingsRepo = InMemorySettingsRepository();
    notifications = _FakeNotifications();

    service = DataLimitService(
      limitRepo,
      usageRepo,
      alertRepo,
      settingsRepo,
      notifications,
    );

    final id = await packageRepo.add(newPackage());
    package = (await packageRepo.getById(id))!;
  });

  group('Fallback batas Data Planner', () {
    test('tanpa batas manual memakai target harian planner', () async {
      final evaluation = await service.evaluate(
        packageId: package.id!,
        usedBytes: 90 * kBytesPerMB,
        plannerResult: _planner(),
      );

      expect(evaluation.limitSource, DataLimitSource.planner);
      expect(evaluation.limitBytes, hundredMb);
      expect(evaluation.status, DataLimitStatus.warning);
    });

    test('batas manual menjadi prioritas di atas planner', () async {
      await saveLimit(package.id!, dailyLimitBytes: 200 * kBytesPerMB);

      final evaluation = await service.evaluate(
        packageId: package.id!,
        usedBytes: 100 * kBytesPerMB,
        plannerResult: _planner(),
      );

      expect(evaluation.limitSource, DataLimitSource.manual);
      expect(evaluation.limitBytes, 200 * kBytesPerMB);
      expect(evaluation.status, DataLimitStatus.normal);
    });

    test('menghapus batas manual kembali ke target planner', () async {
      await saveLimit(package.id!);
      expect(
        (await service.evaluate(
          packageId: package.id!,
          usedBytes: 10 * kBytesPerMB,
          plannerResult: _planner(),
        )).limitSource,
        DataLimitSource.manual,
      );

      await service.clearDailyLimit(package.id!);

      final evaluation = await service.evaluate(
        packageId: package.id!,
        usedBytes: 10 * kBytesPerMB,
        plannerResult: _planner(),
      );

      expect(evaluation.limitSource, DataLimitSource.planner);
      expect(evaluation.limitBytes, hundredMb);
    });

    test(
      'menyimpan batas manual kosong mengaktifkan fallback planner',
      () async {
        await saveLimit(package.id!, dailyLimitBytes: null);

        final evaluation = await service.evaluate(
          packageId: package.id!,
          usedBytes: 85 * kBytesPerMB,
          plannerResult: _planner(),
        );

        expect(evaluation.limitSource, DataLimitSource.planner);
        expect(evaluation.alertType, AlertType.daily80);
      },
    );

    test('paket kedaluwarsa tidak memicu evaluasi dari planner', () async {
      for (final planner in [
        _planner(dailyTarget: null, status: PlannerStatus.expired),
        _planner(status: PlannerStatus.notStarted),
      ]) {
        final evaluation = await service.evaluateAndNotify(
          packageId: package.id!,
          userId: userId,
          usedBytes: 5 * kBytesPerGB,
          plannerResult: planner,
        );

        expect(evaluation.status, DataLimitStatus.noLimit);
        expect(evaluation.limitBytes, isNull);
        expect(evaluation.alertType, isNull);
      }

      expect(notifications.bodies, isEmpty);
      expect(await alertRepo.getByPackage(package.id!), isEmpty);
    });

    test('target planner tidak valid (0/null) tidak dievaluasi', () async {
      final evaluation = await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: hundredMb,
        plannerResult: _planner(dailyTarget: 0),
      );

      expect(evaluation.status, DataLimitStatus.noLimit);
      expect(notifications.bodies, isEmpty);
    });
  });

  group('Batas paket tidak bocor ke paket lain', () {
    test('paket baru tidak memakai batas paket sebelumnya', () async {
      await saveLimit(package.id!, dailyLimitBytes: 500 * kBytesPerMB);

      final newId = await packageRepo.add(newPackage(name: 'Paket Baru'));
      final activePackage = (await packageRepo.getById(newId))!;

      final provider = DataLimitProvider(service);
      await provider.load(activePackage, userId);

      expect(provider.setting, isNull);
      expect(provider.usesPlannerTarget, isTrue);
      expect(provider.usesManualLimit, isFalse);
      expect(provider.evaluation?.limitBytes, isNot(500 * kBytesPerMB));
    });
  });

  group('Notifikasi tidak berulang', () {
    test('id notifikasi stabil untuk kejadian yang sama', () {
      final first = alertNotificationId(
        packageId: 'pkg-1',
        type: AlertType.daily80,
        date: DateTime(2026, 3, 4, 9),
      );
      final second = alertNotificationId(
        packageId: 'pkg-1',
        type: AlertType.daily80,
        date: DateTime(2026, 3, 4, 21),
      );

      expect(first, second);
      expect(first, greaterThan(0));

      expect(
        alertNotificationId(
          packageId: 'pkg-1',
          type: AlertType.daily100,
          date: DateTime(2026, 3, 4),
        ),
        isNot(first),
      );

      expect(
        alertNotificationId(
          packageId: 'pkg-1',
          type: AlertType.daily80,
          date: DateTime(2026, 3, 5),
        ),
        isNot(first),
      );
    });

    test('evaluasi berulang pada hari yang sama hanya sekali', () async {
      await saveLimit(package.id!);

      for (var i = 0; i < 5; i++) {
        await service.evaluateAndNotify(
          packageId: package.id!,
          userId: userId,
          usedBytes: 85 * kBytesPerMB,
        );
      }

      expect(notifications.bodies.length, 1);
      expect((await alertRepo.getByPackage(package.id!)).length, 1);
    });

    test('alert tetap tersimpan walau notifikasi gagal dikirim', () async {
      await saveLimit(package.id!);
      notifications.deliver = false;

      await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 85 * kBytesPerMB,
      );

      final logs = await alertRepo.getByPackage(package.id!);
      expect(
        logs.length,
        1,
        reason: 'riwayat Notification Center dipertahankan',
      );

      // Notifikasi tidak boleh dibuat ulang hanya karena ada refresh.
      notifications.deliver = true;
      await service.evaluateAndNotify(
        packageId: package.id!,
        userId: userId,
        usedBytes: 90 * kBytesPerMB,
      );

      expect(notifications.bodies, isEmpty);
      expect((await alertRepo.getByPackage(package.id!)).length, 1);
    });
  });

  group('Evaluasi latar belakang tanpa Dashboard', () {
    test('paket aktif dievaluasi dan alert dibuat', () async {
      await saveLimit(package.id!);

      final now = DateTime.now();
      await usageRepo.upsertRecord(
        UsageRecord(
          packageId: package.id!,
          recordScope: UsageRecordScope.deviceTotal,
          networkType: NetworkType.mobile,
          periodStartAt: dateOnly(now),
          periodEndAt: now.add(const Duration(seconds: 1)),
          rxBytes: 90 * kBytesPerMB,
          txBytes: 0,
          source: UsageSource.android,
          sourceKey: 'device-bg',
          recordedAt: now,
        ),
      );

      final evaluated = await DataLimitBackgroundRunner.evaluate(
        packageRepo: packageRepo,
        dataLimitService: service,
      );

      expect(evaluated, 1);
      expect(notifications.bodies.length, 1);
      expect(
        (await alertRepo.getByPackage(package.id!)).single.alertType,
        'DAILY80',
      );

      // Worker berjalan lagi: tidak ada notifikasi atau alert baru.
      await DataLimitBackgroundRunner.evaluate(
        packageRepo: packageRepo,
        dataLimitService: service,
      );

      expect(notifications.bodies.length, 1);
      expect((await alertRepo.getByPackage(package.id!)).length, 1);
    });

    test('paket dengan peringatan nonaktif tidak menghasilkan alert', () async {
      await saveLimit(package.id!, isEnabled: false);

      final evaluated = await DataLimitBackgroundRunner.evaluate(
        packageRepo: packageRepo,
        dataLimitService: service,
      );

      // Paket tetap dievaluasi (statusnya `disabled`); penyaringan peringatan
      // terjadi di evaluateAndNotify, bukan di worker.
      expect(evaluated, 1);
      expect(notifications.bodies, isEmpty);
      expect(await alertRepo.getByPackage(package.id!), isEmpty);
    });
  });

  group('DataLimitProvider - sumber batas di UI', () {
    test('memuat fallback planner tanpa perlu Dashboard', () async {
      final provider = DataLimitProvider(service);

      await provider.load(package, userId);

      expect(provider.evaluation, isNotNull);
      expect(provider.usesPlannerTarget, isTrue);
      expect(provider.evaluation!.limitBytes, isNotNull);
      expect(provider.plannerDailyTargetBytes, isNotNull);
    });

    test('batas manual lalu dikosongkan kembali ke planner', () async {
      final provider = DataLimitProvider(service);
      await provider.load(package, userId);

      final savedManual = await provider.save(
        packageId: package.id!,
        userId: userId,
        isEnabled: true,
        dailyLimitBytes: 250 * kBytesPerMB,
        warnAtPercent: 80,
      );

      expect(savedManual, isTrue);
      expect(provider.usesManualLimit, isTrue);
      expect(provider.evaluation?.limitBytes, 250 * kBytesPerMB);

      final savedPlanner = await provider.save(
        packageId: package.id!,
        userId: userId,
        isEnabled: true,
        dailyLimitBytes: null,
        warnAtPercent: 80,
      );

      expect(savedPlanner, isTrue);
      expect(provider.usesPlannerTarget, isTrue);
      expect(provider.setting?.dailyLimitBytes, isNull);
    });

    test('peringatan yang dimatikan tidak memakai batas apa pun', () async {
      final provider = DataLimitProvider(service);
      await provider.load(package, userId);

      await provider.save(
        packageId: package.id!,
        userId: userId,
        isEnabled: false,
        dailyLimitBytes: 250 * kBytesPerMB,
        warnAtPercent: 80,
      );

      expect(provider.evaluation?.status, DataLimitStatus.disabled);
      expect(provider.evaluation?.alertType, isNull);
      expect(notifications.bodies, isEmpty);
    });
  });
}
