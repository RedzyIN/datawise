// Perhitungan batas pemakaian harian untuk Dashboard. Fungsi murni: tanpa
// database dan tanpa notifikasi. Layanan penyimpanan/notifikasi berada di
// `data_limit_service.dart`.
import '../models/models.dart';

class DashboardDataLimitStatus {
  const DashboardDataLimitStatus({
    required this.isConfigured,
    required this.limitBytes,
    required this.usedBytes,
    required this.percent,
    required this.shouldWarn,
    required this.isExceeded,
  });

  /// true hanya jika paket memiliki batas harian aktif.
  final bool isConfigured;
  final int limitBytes;
  final int usedBytes;

  /// Pemakaian dalam persen terhadap batas (bisa melebihi 100).
  final double percent;
  final bool shouldWarn;
  final bool isExceeded;

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
  static DashboardDataLimitStatus evaluate(
    DataLimitSetting? setting,
    int todayUsedBytes,
  ) {
    final used = todayUsedBytes < 0 ? 0 : todayUsedBytes;
    final limit = setting?.dailyLimitBytes;

    if (setting == null || !setting.isEnabled || limit == null || limit <= 0) {
      return DashboardDataLimitStatus(
        isConfigured: false,
        limitBytes: limit ?? 0,
        usedBytes: used,
        percent: 0,
        shouldWarn: false,
        isExceeded: false,
      );
    }

    final percent = used * 100 / limit;

    return DashboardDataLimitStatus(
      isConfigured: true,
      limitBytes: limit,
      usedBytes: used,
      percent: percent,
      shouldWarn: percent >= setting.warnAtPercent,
      isExceeded: percent >= setting.limitAtPercent,
    );
  }
}
