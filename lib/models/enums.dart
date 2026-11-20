// Enum dan pemetaan nilai database untuk kontrak DATAWISE v3.

enum UsageSource { android, manual }

enum UsageReadStatus { ok, permissionDenied, unsupported, error }

enum PlannerStatus { normal, notStarted, depleted, expired }

enum AlertType { daily80, daily100, dailyOver, quota10, expiring1d }

enum PackageStatus { active, inactive, expired, archived }

enum QuotaCategoryType { main, night, social, appSpecific, custom }

enum UsageRecordScope { appUsage, deviceTotal, manualTotal }

enum NetworkType { mobile, wifi, unknown }

enum AllocationMethod { autoRule, mainFallback, manualUser, unclassified }

String packageStatusToDb(PackageStatus value) => switch (value) {
  PackageStatus.active => 'ACTIVE',
  PackageStatus.inactive => 'INACTIVE',
  PackageStatus.expired => 'EXPIRED',
  PackageStatus.archived => 'ARCHIVED',
};

PackageStatus packageStatusFromDb(String value) => switch (value) {
  'ACTIVE' => PackageStatus.active,
  'INACTIVE' => PackageStatus.inactive,
  'EXPIRED' => PackageStatus.expired,
  'ARCHIVED' => PackageStatus.archived,
  _ => throw FormatException('Status paket tidak dikenal: $value'),
};

String quotaCategoryTypeToDb(QuotaCategoryType value) => switch (value) {
  QuotaCategoryType.main => 'MAIN',
  QuotaCategoryType.night => 'NIGHT',
  QuotaCategoryType.social => 'SOCIAL',
  QuotaCategoryType.appSpecific => 'APP_SPECIFIC',
  QuotaCategoryType.custom => 'CUSTOM',
};

QuotaCategoryType quotaCategoryTypeFromDb(String value) => switch (value) {
  'MAIN' => QuotaCategoryType.main,
  'NIGHT' => QuotaCategoryType.night,
  'SOCIAL' => QuotaCategoryType.social,
  'APP_SPECIFIC' => QuotaCategoryType.appSpecific,
  'CUSTOM' => QuotaCategoryType.custom,
  _ => throw FormatException('Tipe kategori tidak dikenal: $value'),
};

String usageSourceToDb(UsageSource value) => switch (value) {
  UsageSource.android => 'ANDROID',
  UsageSource.manual => 'MANUAL',
};

UsageSource usageSourceFromDb(String value) => switch (value) {
  'ANDROID' => UsageSource.android,
  'MANUAL' => UsageSource.manual,
  _ => throw FormatException('Sumber pemakaian tidak dikenal: $value'),
};

String usageRecordScopeToDb(UsageRecordScope value) => switch (value) {
  UsageRecordScope.appUsage => 'APP_USAGE',
  UsageRecordScope.deviceTotal => 'DEVICE_TOTAL',
  UsageRecordScope.manualTotal => 'MANUAL_TOTAL',
};

UsageRecordScope usageRecordScopeFromDb(String value) => switch (value) {
  'APP_USAGE' => UsageRecordScope.appUsage,
  'DEVICE_TOTAL' => UsageRecordScope.deviceTotal,
  'MANUAL_TOTAL' => UsageRecordScope.manualTotal,
  _ => throw FormatException('Scope pemakaian tidak dikenal: $value'),
};

String networkTypeToDb(NetworkType value) => switch (value) {
  NetworkType.mobile => 'MOBILE',
  NetworkType.wifi => 'WIFI',
  NetworkType.unknown => 'UNKNOWN',
};

NetworkType networkTypeFromDb(String value) => switch (value) {
  'MOBILE' => NetworkType.mobile,
  'WIFI' => NetworkType.wifi,
  'UNKNOWN' => NetworkType.unknown,
  _ => throw FormatException('Jenis jaringan tidak dikenal: $value'),
};

String allocationMethodToDb(AllocationMethod value) => switch (value) {
  AllocationMethod.autoRule => 'AUTO_RULE',
  AllocationMethod.mainFallback => 'MAIN_FALLBACK',
  AllocationMethod.manualUser => 'MANUAL_USER',
  AllocationMethod.unclassified => 'UNCLASSIFIED',
};

AllocationMethod allocationMethodFromDb(String value) => switch (value) {
  'AUTO_RULE' => AllocationMethod.autoRule,
  'MAIN_FALLBACK' => AllocationMethod.mainFallback,
  'MANUAL_USER' => AllocationMethod.manualUser,
  'UNCLASSIFIED' => AllocationMethod.unclassified,
  _ => throw FormatException('Metode alokasi tidak dikenal: $value'),
};

String alertTypeToDb(AlertType value) => value.name.toUpperCase();

AlertType alertTypeFromDb(String value) {
  final normalized = value.toLowerCase();
  for (final type in AlertType.values) {
    if (type.name == normalized) return type;
  }
  throw FormatException('Tipe alert tidak dikenal: $value');
}
