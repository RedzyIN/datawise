import 'date_codec.dart';
import 'enums.dart';

class UsageAllocation {
  final String? id;
  final String packageId;
  final String usageRecordId;
  final String? quotaCategoryId;
  final String? classificationRuleId;
  final int allocatedBytes;
  final AllocationMethod allocationMethod;
  final DateTime createdAt;

  const UsageAllocation({
    this.id,
    required this.packageId,
    required this.usageRecordId,
    this.quotaCategoryId,
    this.classificationRuleId,
    required this.allocatedBytes,
    required this.allocationMethod,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'package_id': packageId,
    'usage_record_id': usageRecordId,
    'quota_category_id': quotaCategoryId,
    'classification_rule_id': classificationRuleId,
    'allocated_bytes': allocatedBytes,
    'allocation_method': allocationMethodToDb(allocationMethod),
    'created_at': timeToIso(createdAt),
  };

  factory UsageAllocation.fromMap(Map<String, Object?> map) => UsageAllocation(
    id: map['id'] as String,
    packageId: map['package_id'] as String,
    usageRecordId: map['usage_record_id'] as String,
    quotaCategoryId: map['quota_category_id'] as String?,
    classificationRuleId: map['classification_rule_id'] as String?,
    allocatedBytes: map['allocated_bytes'] as int,
    allocationMethod: allocationMethodFromDb(
      map['allocation_method'] as String,
    ),
    createdAt: timeFromIso(map['created_at'] as String),
  );
}
