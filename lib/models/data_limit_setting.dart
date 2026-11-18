import 'date_codec.dart';

class DataLimitSetting {
  final String packageId;
  final int? dailyLimitBytes;
  final int warnAtPercent;
  final int limitAtPercent;
  final bool isEnabled;
  final DateTime updatedAt;

  const DataLimitSetting({
    required this.packageId,
    this.dailyLimitBytes,
    this.warnAtPercent = 80,
    this.limitAtPercent = 100,
    required this.isEnabled,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'package_id': packageId,
    'daily_limit_bytes': dailyLimitBytes,
    'warn_at_percent': warnAtPercent,
    'limit_at_percent': limitAtPercent,
    'is_enabled': isEnabled ? 1 : 0,
    'updated_at': timeToIso(updatedAt),
  };

  factory DataLimitSetting.fromMap(Map<String, Object?> map) =>
      DataLimitSetting(
        packageId: map['package_id'] as String,
        dailyLimitBytes: map['daily_limit_bytes'] as int?,
        warnAtPercent: map['warn_at_percent'] as int,
        limitAtPercent: map['limit_at_percent'] as int,
        isEnabled: (map['is_enabled'] as int) == 1,
        updatedAt: timeFromIso(map['updated_at'] as String),
      );
}
