import 'date_codec.dart';
import 'enums.dart';

const Object _usageUnset = Object();

class UsageRecord {
  final String? id;
  final String packageId;
  final UsageRecordScope recordScope;
  final int? appUid;
  final String? appPackageName;
  final String? appName;
  final NetworkType networkType;
  final DateTime periodStartAt;
  final DateTime periodEndAt;
  final int rxBytes;
  final int txBytes;
  final UsageSource source;
  final String? sourceKey;
  final DateTime recordedAt;

  const UsageRecord({
    this.id,
    required this.packageId,
    required this.recordScope,
    this.appUid,
    this.appPackageName,
    this.appName,
    required this.networkType,
    required this.periodStartAt,
    required this.periodEndAt,
    required this.rxBytes,
    required this.txBytes,
    required this.source,
    this.sourceKey,
    required this.recordedAt,
  });

  int get totalBytes => rxBytes + txBytes;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'package_id': packageId,
    'record_scope': usageRecordScopeToDb(recordScope),
    'app_uid': appUid,
    'app_package_name': appPackageName,
    'app_name': appName,
    'network_type': networkTypeToDb(networkType),
    'period_start_at': timeToIso(periodStartAt),
    'period_end_at': timeToIso(periodEndAt),
    'rx_bytes': rxBytes,
    'tx_bytes': txBytes,
    'source': usageSourceToDb(source),
    'source_key': sourceKey,
    'recorded_at': timeToIso(recordedAt),
  };

  factory UsageRecord.fromMap(Map<String, Object?> map) => UsageRecord(
    id: map['id'] as String,
    packageId: map['package_id'] as String,
    recordScope: usageRecordScopeFromDb(map['record_scope'] as String),
    appUid: map['app_uid'] as int?,
    appPackageName: map['app_package_name'] as String?,
    appName: map['app_name'] as String?,
    networkType: networkTypeFromDb(map['network_type'] as String),
    periodStartAt: timeFromIso(map['period_start_at'] as String),
    periodEndAt: timeFromIso(map['period_end_at'] as String),
    rxBytes: map['rx_bytes'] as int,
    txBytes: map['tx_bytes'] as int,
    source: usageSourceFromDb(map['source'] as String),
    sourceKey: map['source_key'] as String?,
    recordedAt: timeFromIso(map['recorded_at'] as String),
  );

  UsageRecord copyWith({
    Object? id = _usageUnset,
    String? packageId,
    UsageRecordScope? recordScope,
    Object? appUid = _usageUnset,
    Object? appPackageName = _usageUnset,
    Object? appName = _usageUnset,
    NetworkType? networkType,
    DateTime? periodStartAt,
    DateTime? periodEndAt,
    int? rxBytes,
    int? txBytes,
    UsageSource? source,
    Object? sourceKey = _usageUnset,
    DateTime? recordedAt,
  }) => UsageRecord(
    id: identical(id, _usageUnset) ? this.id : id as String?,
    packageId: packageId ?? this.packageId,
    recordScope: recordScope ?? this.recordScope,
    appUid: identical(appUid, _usageUnset) ? this.appUid : appUid as int?,
    appPackageName: identical(appPackageName, _usageUnset)
        ? this.appPackageName
        : appPackageName as String?,
    appName: identical(appName, _usageUnset)
        ? this.appName
        : appName as String?,
    networkType: networkType ?? this.networkType,
    periodStartAt: periodStartAt ?? this.periodStartAt,
    periodEndAt: periodEndAt ?? this.periodEndAt,
    rxBytes: rxBytes ?? this.rxBytes,
    txBytes: txBytes ?? this.txBytes,
    source: source ?? this.source,
    sourceKey: identical(sourceKey, _usageUnset)
        ? this.sourceKey
        : sourceKey as String?,
    recordedAt: recordedAt ?? this.recordedAt,
  );
}
