import 'package:datawise/services/alert_service.dart';
import 'package:datawise/services/alert_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSink implements NotificationSink {
  _FakeSink({this.deliver = true});

  final bool deliver;
  final List<String> titles = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> show(int id, String title, String body) async {
    if (!deliver) return false;

    titles.add(title);
    return true;
  }
}

void main() {
  // Repository memvalidasi masa aktif terhadap jam nyata, jadi simulasi
  // memakai waktu berjalan; seluruh tanggal simulasi tetap dihitung relatif
  // terhadap satu titik waktu yang sama.
  final now = DateTime.now();

  test('seluruh skenario simulasi lolos dengan aturan produksi', () async {
    final sink = _FakeSink();
    final simulator = AlertSimulator(sink: sink, now: () => now);

    final results = await simulator.runAll();

    expect(results, hasLength(AlertSimulationScenario.values.length));

    for (final result in results) {
      expect(result.passed, isTrue, reason: result.detail);
      expect(result.logs, hasLength(1), reason: result.scenario.label);
      expect(result.notifications, hasLength(1));
    }

    final types = {for (final result in results) result.logs.single.alertType};

    expect(types, {'DAILY100', 'DAILYOVER', 'QUOTA20', 'EXPIRING1D'});
  });

  test('skenario duplikasi membuktikan dedupe mencegah pengulangan', () async {
    final sink = _FakeSink();
    final simulator = AlertSimulator(sink: sink, now: () => now);

    final result = await simulator.run(AlertSimulationScenario.duplicateEvent);

    expect(result.passed, isTrue);
    expect(result.logs, hasLength(1));
    expect(result.notifications, hasLength(1));
    expect(result.repeatLogs, 1);
    expect(result.repeatNotifications, 0);
    expect(sink.titles, hasLength(1));
  });

  test('sisa kuota 15% tercatat sebagai QUOTA20', () async {
    final simulator = AlertSimulator(sink: _FakeSink(), now: () => now);

    final result = await simulator.run(AlertSimulationScenario.mainQuota15);

    expect(result.passed, isTrue);
    expect(result.logs.single.alertType, 'QUOTA20');
  });

  test(
    'simulasi melaporkan kegagalan ketika notifikasi tidak terkirim',
    () async {
      final simulator = AlertSimulator(
        sink: _FakeSink(deliver: false),
        now: () => now,
      );

      final result = await simulator.run(
        AlertSimulationScenario.dailyTarget120,
      );

      expect(result.passed, isFalse);
      // Riwayat AlertLog dipertahankan walau notifikasi gagal ditampilkan.
      expect(result.logs.length, 1);
      expect(result.notifications, isEmpty);
    },
  );
}
