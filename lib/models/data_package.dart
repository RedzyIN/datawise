import 'date_codec.dart';
import 'enums.dart';

const Object _packageUnset = Object();

class DataPackage {
  final String? id;
  final String userId;
  final String packageName;
  final String? operatorName;
  final int advertisedTotalQuotaBytes;
  final DateTime startDate;
  final DateTime endDate;
  final PackageStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DataPackage({
    this.id,
    required this.userId,
    required this.packageName,
    this.operatorName,
    required this.advertisedTotalQuotaBytes,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'package_name': packageName,
    'operator_name': operatorName,
    'advertised_total_quota_bytes': advertisedTotalQuotaBytes,
    'start_date': dateToDb(startDate),
    'end_date': dateToDb(endDate),
    'status': packageStatusToDb(status),
    'created_at': timeToIso(createdAt),
    'updated_at': timeToIso(updatedAt),
  };

  factory DataPackage.fromMap(Map<String, Object?> map) => DataPackage(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    packageName: map['package_name'] as String,
    operatorName: map['operator_name'] as String?,
    advertisedTotalQuotaBytes: map['advertised_total_quota_bytes'] as int,
    startDate: dateFromDb(map['start_date'] as String),
    endDate: dateFromDb(map['end_date'] as String),
    status: packageStatusFromDb(map['status'] as String),
    createdAt: timeFromIso(map['created_at'] as String),
    updatedAt: timeFromIso(map['updated_at'] as String),
  );

  DataPackage copyWith({
    Object? id = _packageUnset,
    String? userId,
    String? packageName,
    Object? operatorName = _packageUnset,
    int? advertisedTotalQuotaBytes,
    DateTime? startDate,
    DateTime? endDate,
    PackageStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DataPackage(
    id: identical(id, _packageUnset) ? this.id : id as String?,
    userId: userId ?? this.userId,
    packageName: packageName ?? this.packageName,
    operatorName: identical(operatorName, _packageUnset)
        ? this.operatorName
        : operatorName as String?,
    advertisedTotalQuotaBytes:
        advertisedTotalQuotaBytes ?? this.advertisedTotalQuotaBytes,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
