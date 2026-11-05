// MILIK ARSITEK. KONTRAK BEKU #3. Hasil hitungan (Anggota B).
import 'enums.dart';

class PlannerResult {
  final PlannerStatus status;
  final int totalBytes, usedBytes, remainingBytes;
  final int remainingDays;
  final double? dailyTargetBytes; // null = tidak dihitung
  final double? weeklyTargetBytes;
  final int todayUsedBytes;
  final double usagePercent; // 0.0 - 100.0 dari total kuota
  final double? todayPercentOfTarget; // null jika target null/0 (skala 0-100+)

  const PlannerResult({
    required this.status,
    required this.totalBytes,
    required this.usedBytes,
    required this.remainingBytes,
    required this.remainingDays,
    required this.dailyTargetBytes,
    required this.weeklyTargetBytes,
    required this.todayUsedBytes,
    required this.usagePercent,
    required this.todayPercentOfTarget,
  });
}
