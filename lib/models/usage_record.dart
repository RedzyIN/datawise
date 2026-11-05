// MILIK ARSITEK. KONTRAK BEKU #3.
import 'date_codec.dart';
import 'enums.dart';

class UsageRecord {
  final int? id;
  final int packageId;
  final DateTime recordDate;
  final int usedBytes;
  final UsageSource source;
  final DateTime updatedAt;

  const UsageRecord({
    this.id,
    required this.packageId,
    required this.recordDate,
    required this.usedBytes,
    required this.source,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'package_id': packageId,
        'record_date': dateToDb(recordDate),
        'used_bytes': usedBytes,
        'source': source.name,
        'updated_at': timeToMs(updatedAt),
      };

  factory UsageRecord.fromMap(Map<String, Object?> m) => UsageRecord(
        id: m['id'] as int?,
        packageId: m['package_id'] as int,
        recordDate: dateFromDb(m['record_date'] as String),
        usedBytes: m['used_bytes'] as int,
        source: UsageSource.values.byName(m['source'] as String),
        updatedAt: timeFromMs(m['updated_at'] as int),
      );

  UsageRecord copyWith({
    int? id,
    int? packageId,
    DateTime? recordDate,
    int? usedBytes,
    UsageSource? source,
    DateTime? updatedAt,
  }) =>
      UsageRecord(
        id: id ?? this.id,
        packageId: packageId ?? this.packageId,
        recordDate: recordDate ?? this.recordDate,
        usedBytes: usedBytes ?? this.usedBytes,
        source: source ?? this.source,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
