import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSink implements NotificationSink {
  final List<String> shown = [];
  bool inited = false;

  @override
  Future<void> init() async {
    inited = true;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show(int id, String title, String body) async {
    shown.add(title);
  }
}

void main() {
  final today = DateTime(2026, 11, 17);

  late InMemoryPackageRepository packages;
  late InMemoryAlertRepository alerts;
  late InMemorySettingsRepository settings;
  late _FakeSink sink;
  late AlertServiceImpl service;

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

  setUp(() {
    packages = InMemoryPackageRepository();
    alerts = InMemoryAlertRepository(packages);
    settings = InMemorySettingsRepository();
    sink = _FakeSink();

    service = AlertServiceImpl(alerts, settings, sink: sink, now: () => today);
  });

  test('di bawah 80% tidak ada notifikasi', () async {
    await service.evaluateAndNotify('u', pkg(), plan(pct: 79.9));

    expect(sink.shown, isEmpty);
  });

  test(
    '80%, 100%, dan lebih dari 100,5% memicu jenis alert yang tepat',
    () async {
      await service.evaluateAndNotify('u', pkg(), plan(pct: 85));

      expect(sink.shown, ['Mendekati target harian']);

      await service.evaluateAndNotify('u', pkg(), plan(pct: 100.2));

      expect(sink.shown.last, 'Target harian tercapai');

      await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

      expect(sink.shown.last, 'Target harian terlampaui');
      expect(sink.shown.length, 3);
    },
  );

  test('dedupe mencegah alert harian terkirim berulang', () async {
    await service.evaluateAndNotify('u', pkg(), plan(pct: 90));
    await service.evaluateAndNotify('u', pkg(), plan(pct: 92));

    expect(sink.shown.length, 1);
  });

  test('hanya satu peringatan harian dikirim', () async {
    await service.evaluateAndNotify('u', pkg(), plan(pct: 150));

    expect(sink.shown, ['Target harian terlampaui']);
  });

  test('sisa kuota tepat 10% memicu quota10', () async {
    await service.evaluateAndNotify('u', pkg(), plan(remaining: 3000000000));

    expect(sink.shown, ['Sisa kuota menipis']);

    expect(
      await alerts.existsByDedupeKey('package-1:quota10:2026-11-30'),
      isTrue,
    );
  });

  test('sisa kuota 10,1% tidak memicu quota10', () async {
    await service.evaluateAndNotify('u', pkg(), plan(remaining: 3030000000));

    expect(sink.shown, isEmpty);
  });

  test('paket berakhir besok memicu expiring1d', () async {
    await service.evaluateAndNotify(
      'u',
      pkg(end: DateTime(2026, 11, 18)),
      plan(),
    );

    expect(sink.shown, ['Paket berakhir besok']);
  });

  test('notifikasi yang dinonaktifkan tidak dikirim', () async {
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

    await service.evaluateAndNotify('u', pkg(), plan(pct: 150));

    expect(sink.shown, isEmpty);
  });

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

    await service.evaluateAndNotify('u', pkg(), plan(pct: 150));

    expect(sink.shown, ['Target harian terlampaui']);
  });

  test('paket kedaluwarsa dan belum mulai tidak memicu alert', () async {
    await service.evaluateAndNotify(
      'u',
      pkg(),
      plan(pct: 150, status: PlannerStatus.expired),
    );

    await service.evaluateAndNotify(
      'u',
      pkg(),
      plan(pct: 150, status: PlannerStatus.notStarted),
    );

    expect(sink.shown, isEmpty);
  });
}
