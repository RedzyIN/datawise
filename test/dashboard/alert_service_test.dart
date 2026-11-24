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
  late InMemoryQuotaCategoryRepository categories;
  late InMemoryUsageRepository usage;
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
      now: () => today,
    );
  });

  test('di bawah target harian tidak memicu alert', () async {
    await service.evaluateAndNotify('u', pkg(), plan(pct: 79.9));

    expect(sink.shown, isEmpty);
  });

  test('target harian tercapai memicu daily100', () async {
    await service.evaluateAndNotify('u', pkg(), plan(pct: 100));

    expect(sink.shown, ['Target harian tercapai']);

    expect(
      await alerts.existsByDedupeKey('package-1:daily100:2026-11-17'),
      isTrue,
    );
  });

  test('target harian terlampaui memicu dailyOver', () async {
    await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

    expect(sink.shown, ['Target harian terlampaui']);

    expect(
      await alerts.existsByDedupeKey('package-1:dailyOver:2026-11-17'),
      isTrue,
    );
  });

  test('dedupe mencegah alert harian terkirim berulang', () async {
    await service.evaluateAndNotify('u', pkg(), plan(pct: 100));
    await service.evaluateAndNotify('u', pkg(), plan(pct: 100));

    expect(sink.shown.length, 1);
  });

  test('sisa kuota MAIN tepat 20% memicu quota alert', () async {
    await setMainUsage(24000000000);

    await service.evaluateAndNotify('u', pkg(), plan());

    expect(sink.shown, ['Sisa kuota utama menipis']);

    final logs = await alerts.getByPackage('package-1');

    expect(logs.length, 1);
    expect(logs.first.alertType, 'QUOTA10');
    expect(logs.first.observedBytes, 6000000000);
    expect(logs.first.thresholdBytes, 6000000000);
    expect(logs.first.quotaCategoryId, isNotNull);

    expect(
      await alerts.existsByDedupeKey('package-1:quota10:2026-11-17'),
      isTrue,
    );
  });

  test('sisa kuota MAIN lebih dari 20% tidak memicu alert', () async {
    await setMainUsage(23700000000);

    await service.evaluateAndNotify('u', pkg(), plan());

    expect(sink.shown, isEmpty);
  });

  test('sisa kuota MAIN di bawah 20% memicu alert', () async {
    await setMainUsage(25000000000);

    await service.evaluateAndNotify('u', pkg(), plan());

    expect(sink.shown, ['Sisa kuota utama menipis']);
  });

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

    await service.evaluateAndNotify('u', pkg(), plan(pct: 120));

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
}
