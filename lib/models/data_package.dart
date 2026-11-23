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

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get isArchived => status == PackageStatus.archived;

  /// Kedaluwarsa jika status EXPIRED atau tanggal berakhir sudah lewat.
  bool isExpiredAt([DateTime? now]) {
    final today = _dateOnly(now ?? DateTime.now());
    return status == PackageStatus.expired ||
        _dateOnly(endDate).isBefore(today);
  }

  /// Sisa hari sampai tanggal berakhir (minimal 0).
  int daysRemaining([DateTime? now]) {
    final today = _dateOnly(now ?? DateTime.now());
    final diff = _dateOnly(endDate).difference(today).inDays;
    return diff < 0 ? 0 : diff;
  }

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
