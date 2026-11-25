// Perhitungan batas pemakaian harian untuk Dashboard. Fungsi murni: tanpa
// database dan tanpa notifikasi. Layanan penyimpanan/notifikasi berada di
// `data_limit_service.dart`.
import '../models/models.dart';

/// Asal angka batas harian yang dipakai.
///
/// [planner] berarti pengguna belum menetapkan batas sendiri sehingga target
/// harian Data Planner dipakai sebagai fallback.
enum DataLimitSource { none, manual, planner }

/// Nada status batas harian (dipakai badge Dashboard dan halaman Data Limit).
enum DataLimitTone { unknown, safe, warning, danger }

class DashboardDataLimitStatus {
  const DashboardDataLimitStatus({
    required this.isConfigured,
    required this.limitBytes,
    required this.usedBytes,
    required this.percent,
    required this.shouldWarn,
    required this.isExceeded,
    this.source = DataLimitSource.none,
  });

  /// true jika ada batas harian yang valid (manual atau fallback planner).
  final bool isConfigured;
  final int limitBytes;
  final int usedBytes;

  /// Pemakaian dalam persen terhadap batas (bisa melebihi 100).
  final double percent;
  final bool shouldWarn;
  final bool isExceeded;
  final DataLimitSource source;

  /// Ambang warna badge: di bawah 80% aman, 80%–<100% peringatan,
  /// 100% atau lebih bahaya. Nilai tidak valid tidak diberi status.
  DataLimitTone get tone => toneForPercent(isConfigured ? percent : null);

  static const DashboardDataLimitStatus none = DashboardDataLimitStatus(
    isConfigured: false,
    limitBytes: 0,
    usedBytes: 0,
    percent: 0,
    shouldWarn: false,
    isExceeded: false,
  );
}

class DashboardDataLimitCalculator {
  /// [todayUsedBytes] harus berasal dari catatan pemakaian yang tersimpan.
  ///
  /// Batas manual (`dailyLimitBytes`) menjadi prioritas; bila tidak ada,
  /// [plannerDailyTargetBytes] dipakai sebagai fallback Data Planner.
  static DashboardDataLimitStatus evaluate(
    DataLimitSetting? setting,
    int todayUsedBytes, {
    double? plannerDailyTargetBytes,
  }) {
    final used = todayUsedBytes < 0 ? 0 : todayUsedBytes;

    final manualLimit = setting?.dailyLimitBytes;
    final manualValid = manualLimit != null && manualLimit > 0;

    final plannerLimit =
        plannerDailyTargetBytes != null && plannerDailyTargetBytes > 0
        ? plannerDailyTargetBytes.round()
        : null;

    // Pengaturan yang dimatikan pengguna menghentikan peringatan, termasuk
    // fallback planner: pengguna secara eksplisit mematikan fitur ini.
    final enabled = setting?.isEnabled ?? true;

    final limit = enabled ? (manualValid ? manualLimit : plannerLimit) : null;
    final source = !enabled
        ? DataLimitSource.none
        : manualValid
        ? DataLimitSource.manual
        : plannerLimit != null
        ? DataLimitSource.planner
        : DataLimitSource.none;

    if (limit == null || limit <= 0) {
      return DashboardDataLimitStatus(
        isConfigured: false,
        limitBytes: limit ?? 0,
        usedBytes: used,
        percent: 0,
        shouldWarn: false,
        isExceeded: false,
        source: source,
      );
    }

    final percent = used * 100 / limit;
    final warnAt = setting?.warnAtPercent ?? 80;
    final limitAt = setting?.limitAtPercent ?? 100;

    return DashboardDataLimitStatus(
      isConfigured: true,
      limitBytes: limit,
      usedBytes: used,
      percent: percent,
      shouldWarn: percent >= warnAt,
      isExceeded: percent >= limitAt,
      source: source,
    );
  }
}

/// Nada status untuk persentase pemakaian terhadap batas harian.
///
/// `null` (persentase belum dapat dihitung) menghasilkan
/// [DataLimitTone.unknown] sehingga UI tidak boleh menampilkan warna aman.
DataLimitTone toneForPercent(double? percent) {
  if (percent == null || percent.isNaN || percent.isInfinite) {
    return DataLimitTone.unknown;
  }

  final value = percent < 0 ? 0.0 : percent;

  if (value >= 100) return DataLimitTone.danger;
  if (value >= 80) return DataLimitTone.warning;
  return DataLimitTone.safe;
}
