import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSink implements NotificationSink {
  final List<String> shown = [];
  bool inited = false;
  @override
  Future<void> init() async => inited = true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(int id, String title, String body) async => shown.add(title);
}

void main() {
  final today = DateTime(2026, 11, 17);
  late InMemoryAlertRepository alerts;
  late InMemorySettingsRepository settings;
  late _FakeSink sink;
  late AlertServiceImpl service;

  DataPackage pkg({DateTime? end}) => DataPackage(
        id: 1,
        userId: 'u',
        name: 'Paket 30 GB',
        operator: 'Telkomsel',
        totalBytes: 30000000000,
        initialUsedBytes: 0,
        startDate: DateTime(2026, 11, 1),
        endDate: end ?? DateTime(2026, 11, 30),
        price: null,
        isActive: true,
        createdAt: today,
        updatedAt: today,
      );

  PlannerResult plan({
    double? pct,
    int remaining = 20000000000,
    PlannerStatus status = PlannerStatus.normal,
  }) =>
      PlannerResult(
        status: status,
        totalBytes: 30000000000,
        usedBytes: 30000000000 - remaining,
        remainingBytes: remaining,
        remainingDays: 13,
        dailyTargetBytes: 1500000000,
        weeklyTargetBytes: 10500000000,
        todayUsedBytes: 0,
        usagePercent: 0,
        todayPercentOfTarget: pct,
      );

  setUp(() {
    alerts = InMemoryAlertRepository();
    settings = InMemorySettingsRepository();
    sink = _FakeSink();
    service = AlertServiceImpl(alerts, settings, sink: sink, now: () => today);
  });

  test('di bawah 80% tidak ada notifikasi', () async {
    await service.evaluateAndNotify(pkg(), plan(pct: 79.9));
    expect(sink.shown, isEmpty);
  });

  test('80% -> daily80, 100% -> daily100, >100,5% -> dailyOver', () async {
    await service.evaluateAndNotify(pkg(), plan(pct: 85));
    expect(sink.shown, ['Mendekati target harian']);
    await service.evaluateAndNotify(pkg(), plan(pct: 100.2));
    expect(sink.shown.last, 'Target harian tercapai');
    await service.evaluateAndNotify(pkg(), plan(pct: 120));
    expect(sink.shown.last, 'Target harian terlampaui');
    expect(sink.shown.length, 3);
  });

  test('dedupe: jenis & tanggal yang sama hanya dikirim sekali', () async {
    await service.evaluateAndNotify(pkg(), plan(pct: 90));
    await service.evaluateAndNotify(pkg(), plan(pct: 92));
    expect(sink.shown.length, 1);
  });

  test('hanya satu peringatan harian (tingkat tertinggi)', () async {
    await service.evaluateAndNotify(pkg(), plan(pct: 150));
    expect(sink.shown, ['Target harian terlampaui']);
  });

  test('sisa kuota <= 10% -> quota10, tepat 10% ikut', () async {
    await service.evaluateAndNotify(pkg(), plan(remaining: 3000000000));
    expect(sink.shown, ['Sisa kuota menipis']);
    expect(await alerts.hasBeenSent(1, AlertType.quota10, DateTime(2026, 11, 30)), isTrue);
  });

  test('sisa kuota 10,1% -> tidak ada notifikasi', () async {
    await service.evaluateAndNotify(pkg(), plan(remaining: 3030000000));
    expect(sink.shown, isEmpty);
  });

  test('paket berakhir besok -> expiring1d', () async {
    await service.evaluateAndNotify(pkg(end: DateTime(2026, 11, 18)), plan());
    expect(sink.shown, ['Paket berakhir besok']);
  });

  test('notifikasi dimatikan (notif_enabled = 0) -> tidak ada yang dikirim', () async {
    await settings.set('notif_enabled', '0');
    await service.evaluateAndNotify(pkg(), plan(pct: 150));
    expect(sink.shown, isEmpty);
  });

  test('paket kedaluwarsa / belum mulai -> tidak ada notifikasi', () async {
    await service.evaluateAndNotify(pkg(), plan(pct: 150, status: PlannerStatus.expired));
    await service.evaluateAndNotify(pkg(), plan(pct: 150, status: PlannerStatus.notStarted));
    expect(sink.shown, isEmpty);
  });
}
