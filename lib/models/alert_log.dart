import 'date_codec.dart';

class AlertLog {
  final String? id;
  final String packageId;
  final String? quotaCategoryId;
  final String alertType;
  final String message;
  final int? observedBytes;
  final int? thresholdBytes;
  final String dedupeKey;
  final DateTime triggeredAt;
  final bool isRead;

  const AlertLog({
    this.id,
    required this.packageId,
    this.quotaCategoryId,
    required this.alertType,
    required this.message,
    this.observedBytes,
    this.thresholdBytes,
    required this.dedupeKey,
    required this.triggeredAt,
    required this.isRead,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'package_id': packageId,
    'quota_category_id': quotaCategoryId,
    'alert_type': alertType,
    'message': message,
    'observed_bytes': observedBytes,
    'threshold_bytes': thresholdBytes,
    'dedupe_key': dedupeKey,
    'triggered_at': timeToIso(triggeredAt),
    'is_read': isRead ? 1 : 0,
  };

  factory AlertLog.fromMap(Map<String, Object?> map) => AlertLog(
    id: map['id'] as String,
    packageId: map['package_id'] as String,
    quotaCategoryId: map['quota_category_id'] as String?,
    alertType: map['alert_type'] as String,
    message: map['message'] as String,
    observedBytes: map['observed_bytes'] as int?,
    thresholdBytes: map['threshold_bytes'] as int?,
    dedupeKey: map['dedupe_key'] as String,
    triggeredAt: timeFromIso(map['triggered_at'] as String),
    isRead: (map['is_read'] as int) == 1,
  );
}
