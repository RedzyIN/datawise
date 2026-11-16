import 'date_codec.dart';

class ClassificationRule {
  final String? id;
  final String quotaCategoryId;
  final String ruleName;
  final String? appPackageName;
  final int? startMinute;
  final int? endMinute;
  final int daysOfWeekMask;
  final int priority;
  final bool isEnabled;
  final DateTime createdAt;

  const ClassificationRule({
    this.id,
    required this.quotaCategoryId,
    required this.ruleName,
    this.appPackageName,
    this.startMinute,
    this.endMinute,
    this.daysOfWeekMask = 127,
    required this.priority,
    required this.isEnabled,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'quota_category_id': quotaCategoryId,
    'rule_name': ruleName,
    'app_package_name': appPackageName,
    'start_minute': startMinute,
    'end_minute': endMinute,
    'days_of_week_mask': daysOfWeekMask,
    'priority': priority,
    'is_enabled': isEnabled ? 1 : 0,
    'created_at': timeToIso(createdAt),
  };

  factory ClassificationRule.fromMap(Map<String, Object?> map) =>
      ClassificationRule(
        id: map['id'] as String,
        quotaCategoryId: map['quota_category_id'] as String,
        ruleName: map['rule_name'] as String,
        appPackageName: map['app_package_name'] as String?,
        startMinute: map['start_minute'] as int?,
        endMinute: map['end_minute'] as int?,
        daysOfWeekMask: map['days_of_week_mask'] as int,
        priority: map['priority'] as int,
        isEnabled: (map['is_enabled'] as int) == 1,
        createdAt: timeFromIso(map['created_at'] as String),
      );
}
