// PEMILIK: Anggota B. KONTRAK BEKU #1 & #4.
// Fungsi MURNI: tanpa database, tanpa jam sistem. Rumus: lihat dokumen B bagian 4
// dan kerangka acuan di bagian 11.1.
// TODO(B): implementasikan; 10 kasus uji di test/package/planner_service_test.dart
import '../models/models.dart';

class PlannerService {
  static PlannerResult calculate({
    required DataPackage package,
    required int totalUsedBytes,
    required int todayUsedBytes,
    required DateTime today,
  }) {
    final total = package.advertisedTotalQuotaBytes < 0
        ? 0
        : package.advertisedTotalQuotaBytes;
    final used = totalUsedBytes < 0 ? 0 : totalUsedBytes;
    final remaining = total - used < 0 ? 0 : total - used;
    final usedToday = todayUsedBytes < 0 ? 0 : todayUsedBytes;

    final todayDate = _dateOnly(today);
    final startDate = _dateOnly(package.startDate);
    final endDate = _dateOnly(package.endDate);

    // Sisa hari inklusif: hari ini adalah tanggal akhir berarti masih 1 hari.
    final rawRemainingDays = endDate.difference(todayDate).inDays + 1;
    final remainingDays = rawRemainingDays < 0 ? 0 : rawRemainingDays;

    final PlannerStatus status;
    if (remainingDays == 0) {
      status = PlannerStatus.expired;
    } else if (todayDate.isBefore(startDate)) {
      status = PlannerStatus.notStarted;
    } else if (remaining <= 0) {
      status = PlannerStatus.depleted;
    } else {
      status = PlannerStatus.normal;
    }

    // Paket kedaluwarsa tidak memiliki target harian (PRD 4.4).
    final dailyTarget = remainingDays == 0 ? null : remaining / remainingDays;
    final weeklyDays = remainingDays < 7 ? remainingDays : 7;
    final weeklyTarget = dailyTarget == null ? null : dailyTarget * weeklyDays;

    final todayPercentOfTarget = (dailyTarget == null || dailyTarget <= 0)
        ? null
        : usedToday * 100 / dailyTarget;

    final usagePercent = total == 0 ? 0.0 : used * 100 / total;

    return PlannerResult(
      status: status,
      totalBytes: total,
      usedBytes: used,
      remainingBytes: remaining,
      remainingDays: remainingDays,
      dailyTargetBytes: dailyTarget,
      weeklyTargetBytes: weeklyTarget,
      todayUsedBytes: usedToday,
      usagePercent: usagePercent,
      todayPercentOfTarget: todayPercentOfTarget,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class PackageValidator {
  /// null = valid, selain itu pesan error (urutan & teks: dokumen B bagian 11.2).
  static String? validate(DataPackage p) {
    throw UnimplementedError('TODO(B): PackageValidator.validate');
  }
}
