import 'date_codec.dart';
import 'enums.dart';

class AlertLog {
  final int? id;
  final int packageId;
  final AlertType type;
  final DateTime alertDate, sentAt;

  const AlertLog({
    this.id, required this.packageId, required this.type,
    required this.alertDate, required this.sentAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'package_id': packageId, 'alert_type': type.name,
    'alert_date': dateToDb(alertDate), 'sent_at': timeToMs(sentAt),
  };

  factory AlertLog.fromMap(Map<String, Object?> m) => AlertLog(
    id: m['id'] as int?, packageId: m['package_id'] as int,
    type: AlertType.values.byName(m['alert_type'] as String),
    alertDate: dateFromDb(m['alert_date'] as String),
    sentAt: timeFromMs(m['sent_at'] as int),
  );
}
