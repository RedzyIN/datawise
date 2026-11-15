class UsageAllocation {
  final int? id;
  final int usageRecordId, categoryId;
  final String appPackageName;
  final int usedBytes;

  const UsageAllocation({
    this.id, required this.usageRecordId, required this.categoryId,
    this.appPackageName = '', required this.usedBytes,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id, 'usage_record_id': usageRecordId,
    'category_id': categoryId, 'app_package_name': appPackageName,
    'used_bytes': usedBytes,
  };

  factory UsageAllocation.fromMap(Map<String, Object?> m) => UsageAllocation(
    id: m['id'] as int?, usageRecordId: m['usage_record_id'] as int,
    categoryId: m['category_id'] as int,
    appPackageName: m['app_package_name'] as String,
    usedBytes: m['used_bytes'] as int,
  );
}
