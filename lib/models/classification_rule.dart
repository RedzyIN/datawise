import 'date_codec.dart';

class ClassificationRule {
  final int? id;
  final int packageId, categoryId;
  final String appPackageName;
  final int? startMinute, endMinute;
  final int priority;
  final bool isEnabled;
  final DateTime createdAt, updatedAt;

  const ClassificationRule({
    this.id, required this.packageId, required this.categoryId,
    required this.appPackageName, this.startMinute, this.endMinute,
    required this.priority, required this.isEnabled,
    required this.createdAt, required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id, 'package_id': packageId, 'category_id': categoryId,
    'app_package_name': appPackageName, 'start_minute': startMinute,
    'end_minute': endMinute, 'priority': priority,
    'is_enabled': isEnabled ? 1 : 0,
    'created_at': timeToMs(createdAt), 'updated_at': timeToMs(updatedAt),
  };

  factory ClassificationRule.fromMap(Map<String, Object?> m) => ClassificationRule(
    id: m['id'] as int?, packageId: m['package_id'] as int,
    categoryId: m['category_id'] as int,
    appPackageName: m['app_package_name'] as String,
    startMinute: m['start_minute'] as int?, endMinute: m['end_minute'] as int?,
    priority: m['priority'] as int, isEnabled: (m['is_enabled'] as int) == 1,
    createdAt: timeFromMs(m['created_at'] as int),
    updatedAt: timeFromMs(m['updated_at'] as int),
  );
}
