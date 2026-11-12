import 'date_codec.dart';

class DataLimitSetting {
  final int? id;
  final int packageId;
  final int dailyWarningPercent, quotaWarningPercent;
  final bool isEnabled;
  final DateTime updatedAt;

  const DataLimitSetting({
    this.id, required this.packageId, required this.dailyWarningPercent,
    required this.quotaWarningPercent, required this.isEnabled,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id, 'package_id': packageId,
    'daily_warning_percent': dailyWarningPercent,
    'quota_warning_percent': quotaWarningPercent,
    'is_enabled': isEnabled ? 1 : 0, 'updated_at': timeToMs(updatedAt),
  };

  factory DataLimitSetting.fromMap(Map<String, Object?> m) => DataLimitSetting(
    id: m['id'] as int?, packageId: m['package_id'] as int,
    dailyWarningPercent: m['daily_warning_percent'] as int,
    quotaWarningPercent: m['quota_warning_percent'] as int,
    isEnabled: (m['is_enabled'] as int) == 1,
    updatedAt: timeFromMs(m['updated_at'] as int),
  );
}
