import 'date_codec.dart';
import 'enums.dart';

class QuotaCategory {
  final int? id;
  final int packageId;
  final String name;
  final QuotaCategoryType type;
  final int quotaBytes;
  final int? startMinute;
  final int? endMinute;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QuotaCategory({
    this.id, required this.packageId, required this.name, required this.type,
    required this.quotaBytes, this.startMinute, this.endMinute,
    required this.createdAt, required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id, 'package_id': packageId, 'name': name,
    'category_type': type.name, 'quota_bytes': quotaBytes,
    'start_minute': startMinute, 'end_minute': endMinute,
    'created_at': timeToMs(createdAt), 'updated_at': timeToMs(updatedAt),
  };

  factory QuotaCategory.fromMap(Map<String, Object?> m) => QuotaCategory(
    id: m['id'] as int?, packageId: m['package_id'] as int,
    name: m['name'] as String,
    type: QuotaCategoryType.values.byName(m['category_type'] as String),
    quotaBytes: m['quota_bytes'] as int,
    startMinute: m['start_minute'] as int?, endMinute: m['end_minute'] as int?,
    createdAt: timeFromMs(m['created_at'] as int),
    updatedAt: timeFromMs(m['updated_at'] as int),
  );
}
