import '../models/models.dart';
import '../repositories/repositories.dart';

/// Nama tampilan aplikasi. Catatan lama bisa belum punya label, jadi identitas
/// UID diubah menjadi teks yang mudah dibaca alih-alih "uid-10123".
String displayAppName(String packageName, String? appName) {
  final name = appName?.trim();
  if (name != null && name.isNotEmpty) return name;
  if (packageName.startsWith('uid-')) {
    return 'Aplikasi UID ${packageName.substring(4)}';
  }
  return packageName;
}

class AppUsageItem {
  final String appPackageName;
  final String appName;
  final int? uid;
  final int rxBytes;
  final int txBytes;
  final int totalBytes;
  final double share;

  const AppUsageItem({
    required this.appPackageName,
    required this.appName,
    required this.uid,
    required this.rxBytes,
    required this.txBytes,
    required this.totalBytes,
    required this.share,
  });
}

/// Ringkasan rincian per aplikasi satu hari, dihitung langsung dari
/// `usage_records` (bukan tabel baru).
class UsageBreakdown {
  final DateTime day;
  final List<AppUsageItem> apps;
  final int appTotalBytes;
  final int deviceTotalBytes;
  final int manualTotalBytes;
  final DateTime? lastUpdatedAt;

  const UsageBreakdown({
    required this.day,
    required this.apps,
    required this.appTotalBytes,
    required this.deviceTotalBytes,
    required this.manualTotalBytes,
    required this.lastUpdatedAt,
  });

  bool get hasApps => apps.isNotEmpty;

  /// Mode manual tidak menyediakan nama aplikasi.
  bool get manualMode => manualTotalBytes > 0;

  /// Selisih DEVICE_TOTAL terhadap jumlah APP_USAGE, untuk informasi kualitas
  /// data. Nilai ini tidak dialokasikan ulang (PRD 5.3).
  int? get differenceBytes =>
      deviceTotalBytes <= 0 ? null : deviceTotalBytes - appTotalBytes;
}

class UsageBreakdownService {
  UsageBreakdownService(this._usageRepo);

  final UsageRepository _usageRepo;

  Future<UsageBreakdown> build({
    required String packageId,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final start = dateOnly(at);
    final end = start.add(const Duration(days: 1));

    final records = await _usageRepo.getRecordsForPeriod(packageId, start, end);

    final grouped = <String, _AppUsageAggregate>{};
    var deviceTotalBytes = 0;
    var manualTotalBytes = 0;
    DateTime? lastUpdatedAt;

    for (final record in records) {
      if (record.networkType == NetworkType.wifi) continue;

      if (lastUpdatedAt == null || record.recordedAt.isAfter(lastUpdatedAt)) {
        lastUpdatedAt = record.recordedAt;
      }

      switch (record.recordScope) {
        case UsageRecordScope.manualTotal:
          manualTotalBytes += record.totalBytes;
        case UsageRecordScope.deviceTotal:
          deviceTotalBytes += record.totalBytes;
        case UsageRecordScope.appUsage:
          final key = record.appPackageName ?? 'uid-${record.appUid ?? -1}';
          grouped
              .putIfAbsent(
                key,
                () => _AppUsageAggregate(
                  packageName: key,
                  appName: record.appName,
                  uid: record.appUid,
                ),
              )
              .add(record);
      }
    }

    final appTotalBytes = grouped.values.fold<int>(
      0,
      (sum, item) => sum + item.totalBytes,
    );

    final apps =
        grouped.values
            .map(
              (item) => AppUsageItem(
                appPackageName: item.packageName,
                appName: displayAppName(item.packageName, item.appName),
                uid: item.uid,
                rxBytes: item.rxBytes,
                txBytes: item.txBytes,
                totalBytes: item.totalBytes,
                share: appTotalBytes <= 0 ? 0 : item.totalBytes / appTotalBytes,
              ),
            )
            .toList()
          ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    return UsageBreakdown(
      day: start,
      apps: apps,
      appTotalBytes: appTotalBytes,
      deviceTotalBytes: deviceTotalBytes,
      manualTotalBytes: manualTotalBytes,
      lastUpdatedAt: lastUpdatedAt,
    );
  }
}

class _AppUsageAggregate {
  _AppUsageAggregate({
    required this.packageName,
    required this.appName,
    required this.uid,
  });

  final String packageName;
  String? appName;
  final int? uid;

  int rxBytes = 0;
  int txBytes = 0;

  int get totalBytes => rxBytes + txBytes;

  void add(UsageRecord record) {
    rxBytes += record.rxBytes;
    txBytes += record.txBytes;

    // Catatan pertama bisa tanpa label; lengkapi dari catatan lain yang punya
    // nama agar satu aplikasi tidak tampil sebagai UID.
    final name = record.appName?.trim();
    if ((appName == null || appName!.trim().isEmpty) &&
        name != null &&
        name.isNotEmpty) {
      appName = name;
    }
  }
}
