// Perhitungan batas pemakaian harian. Fungsi murni: tanpa database.
import '../models/models.dart';

class DataLimitStatus {
  const DataLimitStatus({
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

  static const DataLimitStatus none = DataLimitStatus(
    isConfigured: false,
    limitBytes: 0,
    usedBytes: 0,
    percent: 0,
    shouldWarn: false,
    isExceeded: false,
  );
}

class DataLimitService {
  /// [todayUsedBytes] harus berasal dari catatan pemakaian yang tersimpan.
  static DataLimitStatus evaluate(
    DataLimitSetting? setting,
    int todayUsedBytes,
  ) {
    final used = todayUsedBytes < 0 ? 0 : todayUsedBytes;
    final limit = setting?.dailyLimitBytes;

    if (setting == null || !setting.isEnabled || limit == null || limit <= 0) {
      return DataLimitStatus(
        isConfigured: false,
        limitBytes: limit ?? 0,
        usedBytes: used,
        percent: 0,
        shouldWarn: false,
        isExceeded: false,
      );
    }

    final percent = used * 100 / limit;

    return DataLimitStatus(
      isConfigured: true,
      limitBytes: limit,
      usedBytes: used,
      percent: percent,
      shouldWarn: percent >= setting.warnAtPercent,
      isExceeded: percent >= setting.limitAtPercent,
    );
  }
}
