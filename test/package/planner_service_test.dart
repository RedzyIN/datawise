import 'package:datawise/models/models.dart';
import 'package:datawise/services/planner_service.dart';
import 'package:flutter_test/flutter_test.dart';

DataPackage _package({
  required DateTime start,
  required DateTime end,
  int totalBytes = 10000000000,
}) {
  return DataPackage(
    id: 'p1',
    userId: 'u1',
    packageName: 'Paket Uji',
    operatorName: 'Telkomsel',
    advertisedTotalQuotaBytes: totalBytes,
    startDate: start,
    endDate: end,
    status: PackageStatus.active,
    createdAt: start,
    updatedAt: start,
  );
}

void main() {
  final today = DateTime(2026, 11, 23);

  test('menghitung sisa hari inklusif, target harian, dan mingguan', () {
    // 18 Des - 23 Nov = 25 hari, inklusif menjadi 26 hari.
    final package = _package(
      start: DateTime(2026, 11, 19),
      end: DateTime(2026, 12, 18),
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 3000000000,
      todayUsedBytes: 2000000000,
      today: today,
    );

    expect(result.status, PlannerStatus.normal);
    expect(result.remainingDays, 26);
    expect(result.remainingBytes, 7000000000);
    expect(result.dailyTargetBytes, closeTo(7000000000 / 26, 0.001));
    expect(result.weeklyTargetBytes, closeTo(7000000000 / 26 * 7, 0.001));
    expect(result.usagePercent, closeTo(30, 0.001));
    // 2 GB dari 7/26 GB per hari = 742,86%.
    expect(
      result.todayPercentOfTarget,
      closeTo(2000000000 * 100 / (7000000000 / 26), 0.001),
    );
  });

  test('hari terakhir paket masih dihitung satu hari', () {
    final package = _package(
      start: today.subtract(const Duration(days: 9)),
      end: today,
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 4000000000,
      todayUsedBytes: 0,
      today: today,
    );

    expect(result.status, PlannerStatus.normal);
    expect(result.remainingDays, 1);
    expect(result.dailyTargetBytes, 6000000000);
    expect(result.weeklyTargetBytes, 6000000000);
  });

  test('paket yang sudah lewat tidak memiliki target', () {
    final package = _package(
      start: today.subtract(const Duration(days: 10)),
      end: today.subtract(const Duration(days: 1)),
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 1000000000,
      todayUsedBytes: 0,
      today: today,
    );

    expect(result.status, PlannerStatus.expired);
    expect(result.remainingDays, 0);
    expect(result.dailyTargetBytes, isNull);
    expect(result.weeklyTargetBytes, isNull);
    expect(result.todayPercentOfTarget, isNull);
  });

  test('kuota habis ditandai depleted tanpa target yang menyesatkan', () {
    final package = _package(
      start: today.subtract(const Duration(days: 2)),
      end: today.add(const Duration(days: 5)),
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 10000000000,
      todayUsedBytes: 500000000,
      today: today,
    );

    expect(result.status, PlannerStatus.depleted);
    expect(result.remainingBytes, 0);
    expect(result.dailyTargetBytes, 0);
    expect(result.todayPercentOfTarget, isNull);
    expect(result.usagePercent, 100);
  });

  test('paket yang belum mulai tidak dianggap berjalan', () {
    final package = _package(
      start: today.add(const Duration(days: 1)),
      end: today.add(const Duration(days: 30)),
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 0,
      todayUsedBytes: 0,
      today: today,
    );

    expect(result.status, PlannerStatus.notStarted);
    expect(result.remainingDays, 31);
  });

  test('pemakaian negatif dianggap nol', () {
    final package = _package(
      start: today,
      end: today.add(const Duration(days: 9)),
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: -5,
      todayUsedBytes: -5,
      today: today,
    );

    expect(result.usedBytes, 0);
    expect(result.todayUsedBytes, 0);
    expect(result.usagePercent, 0);
  });
}
