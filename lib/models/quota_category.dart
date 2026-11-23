import 'date_codec.dart';
import 'enums.dart';

const Object _categoryUnset = Object();

class QuotaCategory {
  final String? id;
  final String packageId;
  final String categoryName;
  final QuotaCategoryType categoryType;
  final int capacityBytes;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final bool isEnabled;
  final DateTime createdAt;

  const QuotaCategory({
    this.id,
    required this.packageId,
    required this.categoryName,
    required this.categoryType,
    required this.capacityBytes,
    this.validFrom,
    this.validUntil,
    required this.isEnabled,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'package_id': packageId,
    'category_name': categoryName,
    'category_type': quotaCategoryTypeToDb(categoryType),
    'capacity_bytes': capacityBytes,
    'valid_from': validFrom == null ? null : dateToDb(validFrom!),
    'valid_until': validUntil == null ? null : dateToDb(validUntil!),
    'is_enabled': isEnabled ? 1 : 0,
    'created_at': timeToIso(createdAt),
  };

  factory QuotaCategory.fromMap(Map<String, Object?> map) => QuotaCategory(
    id: map['id'] as String,
    packageId: map['package_id'] as String,
    categoryName: map['category_name'] as String,
    categoryType: quotaCategoryTypeFromDb(map['category_type'] as String),
    capacityBytes: map['capacity_bytes'] as int,
    validFrom: map['valid_from'] == null
        ? null
        : dateFromDb(map['valid_from'] as String),
    validUntil: map['valid_until'] == null
        ? null
        : dateFromDb(map['valid_until'] as String),
    isEnabled: (map['is_enabled'] as int) == 1,
    createdAt: timeFromIso(map['created_at'] as String),
  );

  QuotaCategory copyWith({
    Object? id = _categoryUnset,
    String? packageId,
    String? categoryName,
    QuotaCategoryType? categoryType,
    int? capacityBytes,
    Object? validFrom = _categoryUnset,
    Object? validUntil = _categoryUnset,
    bool? isEnabled,
    DateTime? createdAt,
  }) => QuotaCategory(
    id: identical(id, _categoryUnset) ? this.id : id as String?,
    packageId: packageId ?? this.packageId,
    categoryName: categoryName ?? this.categoryName,
    categoryType: categoryType ?? this.categoryType,
    capacityBytes: capacityBytes ?? this.capacityBytes,
    validFrom: identical(validFrom, _categoryUnset)
        ? this.validFrom
        : validFrom as DateTime?,
    validUntil: identical(validUntil, _categoryUnset)
        ? this.validUntil
        : validUntil as DateTime?,
    isEnabled: isEnabled ?? this.isEnabled,
    createdAt: createdAt ?? this.createdAt,
  );
}
