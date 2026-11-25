import 'package:datawise/models/models.dart';
import 'package:datawise/services/planner_service.dart';
import 'package:flutter_test/flutter_test.dart';

DataPackage _package({
  required DateTime start,
  required DateTime end,
  int totalBytes = 10000000000,
  PackageStatus status = PackageStatus.active,
}) {
  return DataPackage(
    id: 'p1',
    userId: 'u1',
    packageName: 'Paket Uji',
    operatorName: 'Telkomsel',
    advertisedTotalQuotaBytes: totalBytes,
    startDate: start,
    endDate: end,
    status: status,
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

    // Target belum boleh tampil sebagai target aktif sebelum paket berlaku.
    expect(result.dailyTargetBytes, isNull);
    expect(result.weeklyTargetBytes, isNull);
    expect(result.todayPercentOfTarget, isNull);
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

  test('pemakaian bertambah menurunkan target harian dan mingguan', () {
    // 30 hari masa aktif, hari ini adalah hari kedua (29 hari tersisa).
    final package = _package(
      start: today.subtract(const Duration(days: 1)),
      end: today.add(const Duration(days: 28)),
      totalBytes: 30000000000,
    );

    final before = PlannerService.calculate(
      package: package,
      totalUsedBytes: 1000000000,
      todayUsedBytes: 1000000000,
      today: today,
    );
    final after = PlannerService.calculate(
      package: package,
      totalUsedBytes: 1500000000,
      todayUsedBytes: 1500000000,
      today: today,
    );

    expect(before.remainingDays, 29);
    expect(after.remainingDays, 29);
    expect(before.dailyTargetBytes, closeTo(29000000000 / 29, 0.001));
    expect(after.dailyTargetBytes, closeTo(28500000000 / 29, 0.001));
    expect(after.dailyTargetBytes!, lessThan(before.dailyTargetBytes!));
    expect(
      after.weeklyTargetBytes,
      closeTo(after.dailyTargetBytes! * 7, 0.001),
    );
    expect(after.weeklyTargetBytes!, lessThan(before.weeklyTargetBytes!));
  });

  test('sisa hari berkurang menaikkan target tanpa perubahan pemakaian', () {
    final package = _package(
      start: today.subtract(const Duration(days: 1)),
      end: today.add(const Duration(days: 28)),
      totalBytes: 30000000000,
    );

    final firstDay = PlannerService.calculate(
      package: package,
      totalUsedBytes: 29000000000,
      todayUsedBytes: 0,
      today: today,
    );
    final nextDay = PlannerService.calculate(
      package: package,
      totalUsedBytes: 29000000000,
      todayUsedBytes: 0,
      today: today.add(const Duration(days: 1)),
    );

    expect(firstDay.remainingDays, 29);
    expect(nextDay.remainingDays, 28);
    expect(firstDay.remainingBytes, nextDay.remainingBytes);
    expect(nextDay.dailyTargetBytes!, greaterThan(firstDay.dailyTargetBytes!));
    expect(
      nextDay.weeklyTargetBytes!,
      greaterThan(firstDay.weeklyTargetBytes!),
    );
  });

  test('target mingguan dibatasi sisa hari bila kurang dari tujuh', () {
    final package = _package(
      start: today,
      end: today.add(const Duration(days: 2)),
      totalBytes: 9000000000,
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 3000000000,
      todayUsedBytes: 0,
      today: today,
    );

    expect(result.remainingDays, 3);
    expect(result.dailyTargetBytes, 2000000000);
    expect(result.weeklyTargetBytes, 6000000000);
  });

  test(
    'pemakaian melebihi total kuota tetap depleted tanpa target negatif',
    () {
      final package = _package(
        start: today,
        end: today.add(const Duration(days: 4)),
        totalBytes: 10000000000,
      );

      final result = PlannerService.calculate(
        package: package,
        totalUsedBytes: 12000000000,
        todayUsedBytes: 2000000000,
        today: today,
      );

      expect(result.status, PlannerStatus.depleted);
      expect(result.remainingBytes, 0);
      expect(result.usagePercent, closeTo(120, 0.001));
      expect(result.dailyTargetBytes, 0);
      expect(result.weeklyTargetBytes, 0);
      expect(result.todayPercentOfTarget, isNull);
      expect(result.dailyTargetBytes!, greaterThanOrEqualTo(0));
    },
  );

  test('kuota nol tidak menghasilkan NaN atau Infinity', () {
    final package = _package(
      start: today,
      end: today.add(const Duration(days: 4)),
      totalBytes: 0,
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 0,
      todayUsedBytes: 0,
      today: today,
    );

    expect(result.status, PlannerStatus.depleted);
    expect(result.remainingBytes, 0);
    expect(result.usagePercent, 0);
    expect(result.dailyTargetBytes, 0);
    expect(result.weeklyTargetBytes, 0);
    expect(result.usagePercent.isFinite, isTrue);
    expect(result.dailyTargetBytes!.isFinite, isTrue);
    expect(result.weeklyTargetBytes!.isFinite, isTrue);
  });

  test('status EXPIRED dari database menghentikan target', () {
    final package = _package(
      start: today.subtract(const Duration(days: 5)),
      end: today.add(const Duration(days: 5)),
      status: PackageStatus.expired,
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 1000000000,
      todayUsedBytes: 0,
      today: today,
    );

    expect(result.status, PlannerStatus.expired);
    expect(result.dailyTargetBytes, isNull);
    expect(result.weeklyTargetBytes, isNull);
    expect(result.todayPercentOfTarget, isNull);
  });

  test('pergantian bulan dan tahun tetap menghitung sisa hari', () {
    final endOfYear = DateTime(2026, 12, 31);
    final package = _package(
      start: DateTime(2026, 12, 20),
      end: DateTime(2027, 1, 2),
      totalBytes: 3000000000,
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 0,
      todayUsedBytes: 0,
      today: endOfYear,
    );

    expect(result.remainingDays, 3);
    expect(result.dailyTargetBytes, 1000000000);
    expect(result.weeklyTargetBytes, 3000000000);
  });

  test('tahun kabisat dihitung sesuai tanggal kalender', () {
    final beforeLeapDay = DateTime(2028, 2, 28);
    final package = _package(
      start: DateTime(2028, 2, 1),
      end: DateTime(2028, 3, 1),
      totalBytes: 3000000000,
    );

    final result = PlannerService.calculate(
      package: package,
      totalUsedBytes: 0,
      todayUsedBytes: 0,
      today: beforeLeapDay,
    );

    // 28 Feb -> 1 Mar 2028 = 2 hari, inklusif menjadi 3 hari.
    expect(result.remainingDays, 3);
    expect(result.dailyTargetBytes, 1000000000);
  });
}
