// Simulator event Smart Alerts.
//
// Memakai AlertServiceImpl dan aturan produksi yang sebenarnya, tetapi dengan
// repository in-memory dan data terkontrol. Data simulasi tidak pernah masuk ke
// database pengguna.
import '../core/constants.dart';
import '../models/models.dart';
import '../repositories/in_memory/in_memory_repositories.dart';
import 'alert_service.dart';

enum AlertSimulationScenario {
  dailyTarget100('Target harian mencapai 100%'),
  dailyTarget120('Target harian mencapai 120%'),
  mainQuota20('Sisa kuota utama tepat 20%'),
  mainQuota15('Sisa kuota utama 15%'),
  expiringTomorrow('Paket akan berakhir besok'),
  duplicateEvent('Event yang sama dipicu dua kali');

  const AlertSimulationScenario(this.label);

  final String label;
}

/// Hasil satu skenario simulasi.
class AlertSimulationResult {
  const AlertSimulationResult({
    required this.scenario,
    required this.passed,
    required this.detail,
    required this.notifications,
    required this.logs,
    required this.repeatNotifications,
    required this.repeatLogs,
  });

  final AlertSimulationScenario scenario;
  final bool passed;
  final String detail;

  /// Judul notifikasi yang benar-benar dikirim ke [NotificationSink].
  final List<String> notifications;

  final List<AlertLog> logs;

  /// Notifikasi dan alert tambahan dari evaluasi kedua (skenario duplikasi).
  final int repeatNotifications;
  final int repeatLogs;
}

class AlertSimulator {
  AlertSimulator({NotificationSink? sink, DateTime Function()? now})
    : _sink = sink ?? LocalNotificationSink(),
      _now = now ?? DateTime.now;

  static const String simulationUserId = 'simulasi-smart-alerts';

  final NotificationSink _sink;
  final DateTime Function() _now;

  Future<List<AlertSimulationResult>> runAll() async {
    final results = <AlertSimulationResult>[];

    for (final scenario in AlertSimulationScenario.values) {
      results.add(await run(scenario));
    }

    return results;
  }

  Future<AlertSimulationResult> run(AlertSimulationScenario scenario) async {
    final now = _now();
    final today = dateOnly(now);

    final packages = InMemoryPackageRepository();
    final categories = InMemoryQuotaCategoryRepository(packages);
    final usage = InMemoryUsageRepository(packages, categories);
    final alerts = InMemoryAlertRepository(packages);
    final settings = InMemorySettingsRepository();
    final recorder = _RecordingSink(_sink);

    final endsTomorrow = scenario == AlertSimulationScenario.expiringTomorrow;

    final packageId = await packages.add(
      DataPackage(
        userId: simulationUserId,
        packageName: 'Paket Simulasi 10 GB',
        operatorName: 'Simulasi',
        advertisedTotalQuotaBytes: 10 * kBytesPerGB,
        startDate: today.subtract(const Duration(days: 10)),
        endDate: endsTomorrow
            ? today.add(const Duration(days: 1))
            : today.add(const Duration(days: 20)),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final package = (await packages.getById(packageId))!;

    // Siapkan pemakaian kategori MAIN untuk skenario sisa kuota.
    final usedFraction = switch (scenario) {
      AlertSimulationScenario.mainQuota20 => 0.80,
      AlertSimulationScenario.mainQuota15 => 0.85,
      _ => null,
    };

    if (usedFraction != null) {
      final categoriesOfPackage = await categories.getByPackage(packageId);
      final main = categoriesOfPackage.firstWhere(
        (category) => category.categoryType == QuotaCategoryType.main,
      );
      final usedBytes = (package.advertisedTotalQuotaBytes * usedFraction)
          .round();

      await usage.upsertRecordWithAllocations(
        UsageRecord(
          packageId: packageId,
          recordScope: UsageRecordScope.appUsage,
          appPackageName: 'com.example.simulasi',
          networkType: NetworkType.mobile,
          periodStartAt: today,
          periodEndAt: today.add(const Duration(days: 1)),
          rxBytes: usedBytes,
          txBytes: 0,
          source: UsageSource.android,
          sourceKey: 'simulasi-${scenario.name}',
          recordedAt: now,
        ),
        (usageRecordId) => [
          UsageAllocation(
            packageId: packageId,
            usageRecordId: usageRecordId,
            quotaCategoryId: main.id,
            allocatedBytes: usedBytes,
            allocationMethod: AllocationMethod.mainFallback,
            createdAt: now,
          ),
        ],
      );
    }

    final todayPercent = switch (scenario) {
      AlertSimulationScenario.dailyTarget100 => 100.0,
      AlertSimulationScenario.dailyTarget120 => 120.0,
      AlertSimulationScenario.duplicateEvent => 100.0,
      _ => 40.0,
    };

    const totalBytes = 10 * kBytesPerGB;
    const dailyTarget = 500.0 * kBytesPerMB;

    final plan = PlannerResult(
      status: PlannerStatus.normal,
      totalBytes: totalBytes,
      usedBytes: 2 * kBytesPerGB,
      remainingBytes: 8 * kBytesPerGB,
      remainingDays: 16,
      dailyTargetBytes: dailyTarget,
      weeklyTargetBytes: dailyTarget * 7,
      todayUsedBytes: (dailyTarget * todayPercent / 100).round(),
      usagePercent: 20,
      todayPercentOfTarget: todayPercent,
    );

    final service = AlertServiceImpl(
      alerts,
      settings,
      categoryRepo: categories,
      usageRepo: usage,
      sink: recorder,
      now: () => now,
    );

    await service.evaluateAndNotify(simulationUserId, package, plan);

    final logs = await alerts.getByPackage(packageId);

    final repeatNotifications = recorder.titles.length;
    var repeatLogs = logs.length;

    if (scenario == AlertSimulationScenario.duplicateEvent) {
      // Evaluasi kedua dengan data dan tanggal yang sama.
      await service.evaluateAndNotify(simulationUserId, package, plan);

      repeatLogs = (await alerts.getByPackage(packageId)).length;
    }

    final newNotifications = scenario == AlertSimulationScenario.duplicateEvent
        ? recorder.titles.length - repeatNotifications
        : 0;

    final expectedType = switch (scenario) {
      AlertSimulationScenario.dailyTarget100 => AlertType.daily100,
      AlertSimulationScenario.dailyTarget120 => AlertType.dailyOver,
      AlertSimulationScenario.duplicateEvent => AlertType.daily100,
      AlertSimulationScenario.mainQuota20 => AlertType.quota20,
      AlertSimulationScenario.mainQuota15 => AlertType.quota20,
      AlertSimulationScenario.expiringTomorrow => AlertType.expiring1d,
    };

    final expectedTypeDb = alertTypeToDb(expectedType);

    final bool passed;
    final String detail;

    if (scenario == AlertSimulationScenario.duplicateEvent) {
      passed =
          logs.length == 1 &&
          logs.first.alertType == expectedTypeDb &&
          recorder.titles.length == 1 &&
          repeatLogs == 1 &&
          newNotifications == 0;

      detail =
          'Dua evaluasi menghasilkan ${logs.length} AlertLog dan '
          '${recorder.titles.length} notifikasi. '
          '${newNotifications == 0 ? 'Duplikasi berhasil dicegah.' : 'Duplikasi LOLOS.'}';
    } else {
      passed =
          logs.length == 1 &&
          logs.first.alertType == expectedTypeDb &&
          recorder.titles.length == 1;

      detail =
          'Alert ${logs.isEmpty ? '-' : logs.first.alertType} tersimpan, '
          '${recorder.titles.length} notifikasi terkirim.';
    }

    return AlertSimulationResult(
      scenario: scenario,
      passed: passed,
      detail: detail,
      notifications: recorder.titles,
      logs: logs,
      repeatNotifications: newNotifications,
      repeatLogs: repeatLogs,
    );
  }
}

class _RecordingSink implements NotificationSink {
  _RecordingSink(this._inner);

  final NotificationSink _inner;
  final List<String> titles = [];

  @override
  Future<void> init() => _inner.init();

  @override
  Future<bool> requestPermission() => _inner.requestPermission();

  @override
  Future<bool> show(int id, String title, String body) async {
    final shown = await _inner.show(id, title, body);

    if (shown) titles.add(title);

    return shown;
  }
}
