import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSink implements NotificationSink {
  final List<String> shown = [];
  bool inited = false;

  /// Bila false, notifikasi dianggap gagal dikirim.
  bool deliver = true;

  /// Bila true, plugin notifikasi melempar error.
  bool throwOnShow = false;

  @override
  Future<void> init() async {
    inited = true;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> show(int id, String title, String body) async {
    if (throwOnShow) throw Exception('plugin notifikasi gagal');

    if (!deliver) return false;

    shown.add(title);
    return true;
  }
}

void main() {
  final today = DateTime(2026, 11, 17);

  late InMemoryPackageRepository packages;
  late InMemoryQuotaCategoryRepository categories;
  late InMemoryUsageRepository usage;
  late InMemoryAlertRepository alerts;
  late InMemorySettingsRepository settings;
  late _FakeSink sink;
  late AlertServiceImpl service;

  var now = today;

  DataPackage pkg({DateTime? end}) {
    return DataPackage(
      id: 'package-1',
      userId: 'u',
      packageName: 'Paket 30 GB',
      operatorName: 'Telkomsel',
      advertisedTotalQuotaBytes: 30000000000,
      startDate: DateTime(2026, 11, 1),
      endDate: end ?? DateTime(2026, 11, 30),
      status: PackageStatus.active,
      createdAt: today,
      updatedAt: today,
    );
  }

  PlannerResult plan({
    double? pct,
    int remaining = 20000000000,
    PlannerStatus status = PlannerStatus.normal,
  }) {
    return PlannerResult(
      status: status,
      totalBytes: 30000000000,
      usedBytes: 30000000000 - remaining,
      remainingBytes: remaining,
      remainingDays: 13,
      dailyTargetBytes: 1500000000,
      weeklyTargetBytes: 10500000000,
      todayUsedBytes: 1000000000,
      usagePercent: 0,
      todayPercentOfTarget: pct,
    );
  }

  Future<void> setMainUsage(int usedBytes) async {
    final main = (await categories.getByPackage('package-1')).firstWhere(
      (category) => category.categoryType == QuotaCategoryType.main,
    );

    usage.allocations['allocation-1'] = UsageAllocation(
      id: 'allocation-1',
      packageId: 'package-1',
      usageRecordId: 'usage-1',
      quotaCategoryId: main.id,
      allocatedBytes: usedBytes,
      allocationMethod: AllocationMethod.mainFallback,
      createdAt: today,
    );
  }

  setUp(() async {
    now = today;

    packages = InMemoryPackageRepository();
    categories = InMemoryQuotaCategoryRepository(packages);
    usage = InMemoryUsageRepository(packages, categories);
    alerts = InMemoryAlertRepository(packages);
    settings = InMemorySettingsRepository();
    sink = _FakeSink();

    await packages.add(pkg());

    service = AlertServiceImpl(
      alerts,
      settings,
      categoryRepo: categories,
      usageRepo: usage,
      sink: sink,
      now: () => now,
    );
  });

  group('Aturan target harian', () {
    test('di bawah ambang tidak memicu alert', () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 79.9));

      expect(sink.shown, isEmpty);
      expect(await alerts.getByPackage('package-1'), isEmpty);
    });

    test('mencapai 80% memicu daily80', () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 85));

      expect(sink.shown, ['Pemakaian target harian 80%']);

      final logs = await alerts.getByPackage('package-1');
      expect(logs.single.alertType, 'DAILY80');
    });

    test('mencapai 100% memicu daily100', () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 100));

      expect(sink.shown, ['Target harian tercapai']);
      expect(
        await alerts.existsByDedupeKey('package-1:daily100:2026-11-17'),
        isTrue,
      );
    });

    test('mencapai 120% memicu dailyOver', () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

      expect(sink.shown, ['Target harian terlampaui']);
      expect(
        await alerts.existsByDedupeKey('package-1:dailyOver:2026-11-17'),
        isTrue,
      );
    });
  });

  group('Aturan sisa kuota utama', () {
    test('tepat 20% memicu quota20', () async {
      await setMainUsage(24000000000);

      await service.evaluateAndNotify('u', pkg(), plan());

      expect(sink.shown, ['Sisa kuota utama menipis']);

      final logs = await alerts.getByPackage('package-1');

      expect(logs.length, 1);
      expect(logs.first.alertType, 'QUOTA20');
      expect(logs.first.observedBytes, 6000000000);
      expect(logs.first.thresholdBytes, 6000000000);
      expect(logs.first.quotaCategoryId, isNotNull);

      expect(
        await alerts.existsByDedupeKey('package-1:quota20:2026-11-17'),
        isTrue,
      );
    });

    test('15% memicu quota20', () async {
      await setMainUsage(25500000000);

      await service.evaluateAndNotify('u', pkg(), plan());

      expect(sink.shown, ['Sisa kuota utama menipis']);

      final logs = await alerts.getByPackage('package-1');
      expect(logs.single.alertType, 'QUOTA20');
      expect(logs.single.observedBytes, 4500000000);
    });

    test('25% tidak memicu alert kuota', () async {
      await setMainUsage(22500000000);

      await service.evaluateAndNotify('u', pkg(), plan());

      expect(sink.shown, isEmpty);
    });
  });

  group('Aturan masa aktif paket', () {
    test('paket berakhir besok memicu expiring1d', () async {
      await service.evaluateAndNotify(
        'u',
        pkg(end: DateTime(2026, 11, 18)),
        plan(),
      );

      expect(sink.shown, ['Paket berakhir besok']);
      expect(
        await alerts.existsByDedupeKey('package-1:expiring1d:2026-11-17'),
        isTrue,
      );
    });

    test('paket yang masih lama tidak memicu expiring1d', () async {
      await service.evaluateAndNotify(
        'u',
        pkg(end: DateTime(2026, 11, 20)),
        plan(),
      );

      expect(sink.shown, isEmpty);
    });
  });

  group('Dedupe key', () {
    test('event yang sama pada hari yang sama hanya sekali', () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 100));
      await service.evaluateAndNotify('u', pkg(), plan(pct: 100));
      await service.evaluateAndNotify('u', pkg(), plan(pct: 100));

      expect(sink.shown.length, 1);
      expect((await alerts.getByPackage('package-1')).length, 1);
    });

    test('event yang sama pada hari berikutnya dikirim lagi', () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 100));

      now = DateTime(2026, 11, 18);

      await service.evaluateAndNotify('u', pkg(), plan(pct: 100));

      expect(sink.shown.length, 2);

      final logs = await alerts.getByPackage('package-1');
      expect(logs.map((log) => log.dedupeKey).toSet(), {
        'package-1:daily100:2026-11-17',
        'package-1:daily100:2026-11-18',
      });
    });

    test(
      'dua jenis alert berbeda pada hari yang sama keduanya terkirim',
      () async {
        await setMainUsage(24000000000);

        await service.evaluateAndNotify('u', pkg(), plan(pct: 100));

        expect(sink.shown.length, 2);

        final logs = await alerts.getByPackage('package-1');
        expect(logs.map((log) => log.alertType).toSet(), {
          'QUOTA20',
          'DAILY100',
        });
      },
    );

    test('target 100% lalu 120% menghasilkan dua alert berbeda', () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 100));
      await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

      expect(sink.shown, [
        'Target harian tercapai',
        'Target harian terlampaui',
      ]);

      final logs = await alerts.getByPackage('package-1');
      expect(logs.map((log) => log.alertType).toSet(), {
        'DAILY100',
        'DAILYOVER',
      });
    });

    test('evaluasi Dashboard berulang tidak mengulang alert kuota', () async {
      await setMainUsage(24000000000);

      for (var i = 0; i < 5; i++) {
        await service.evaluateAndNotify('u', pkg(), plan());
      }

      expect(sink.shown.length, 1);
      expect((await alerts.getByPackage('package-1')).length, 1);
    });

    test('pemetaan tipe alert menerima nama lama QUOTA10', () {
      expect(alertTypeFromDb('QUOTA10'), AlertType.quota20);
      expect(alertTypeFromDb('QUOTA20'), AlertType.quota20);
      expect(alertTypeToDb(AlertType.quota20), 'QUOTA20');
      expect(alertTypeOrNull('TIDAK_DIKENAL'), isNull);
    });
  });

  group('Pengaturan dan kegagalan', () {
    test(
      'notifikasi yang dinonaktifkan tidak dikirim dan tidak disimpan',
      () async {
        await settings.upsert(
          UserSetting(
            userId: 'u',
            themeMode: 'light',
            paletteKey: 'default',
            notificationsEnabled: false,
            timezoneId: 'Asia/Makassar',
            updatedAt: today,
          ),
        );

        await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

        expect(sink.shown, isEmpty);
        expect(await alerts.getByPackage('package-1'), isEmpty);
      },
    );

    test('pengaturan pengguna lain tidak mematikan notifikasi', () async {
      await settings.upsert(
        UserSetting(
          userId: 'other-user',
          themeMode: 'light',
          paletteKey: 'default',
          notificationsEnabled: false,
          timezoneId: 'Asia/Makassar',
          updatedAt: today,
        ),
      );

      await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

      expect(sink.shown, ['Target harian terlampaui']);
    });

    test('paket kedaluwarsa dan belum mulai tidak memicu alert', () async {
      await service.evaluateAndNotify(
        'u',
        pkg(),
        plan(pct: 120, status: PlannerStatus.expired),
      );

      await service.evaluateAndNotify(
        'u',
        pkg(),
        plan(pct: 120, status: PlannerStatus.notStarted),
      );

      expect(sink.shown, isEmpty);
    });

    test(
      'plugin notifikasi melempar error tidak membuat aplikasi gagal',
      () async {
        sink.throwOnShow = true;

        await expectLater(
          service.evaluateAndNotify('u', pkg(), plan(pct: 120)),
          completes,
        );

        // Alert yang gagal dikirim tidak boleh menahan dedupe selamanya.
        expect(await alerts.getByPackage('package-1'), isEmpty);
      },
    );

    test('alert dicoba ulang setelah notifikasi gagal dikirim', () async {
      sink.deliver = false;

      await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

      expect(sink.shown, isEmpty);
      expect(await alerts.getByPackage('package-1'), isEmpty);

      sink.deliver = true;

      await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

      expect(sink.shown, ['Target harian terlampaui']);
      expect((await alerts.getByPackage('package-1')).length, 1);
    });

    test('alert tersimpan memiliki seluruh atribut wajib', () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

      final log = (await alerts.getByPackage('package-1')).single;

      expect(log.packageId, 'package-1');
      expect(log.alertType, 'DAILYOVER');
      expect(log.message, isNotEmpty);
      expect(log.observedBytes, 1000000000);
      expect(log.thresholdBytes, 1500000000);
      expect(log.dedupeKey, 'package-1:dailyOver:2026-11-17');
      expect(log.triggeredAt, today);
      expect(log.isRead, isFalse);
    });
  });
}
