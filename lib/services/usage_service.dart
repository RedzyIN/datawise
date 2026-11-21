import 'package:flutter/services.dart';

import '../models/models.dart';

abstract class UsageService {
  Future<bool> hasPermission();

  Future<void> openUsageAccessSettings();

  Future<void> openInternetSettings();

  Future<UsageReading> readMobileUsage(DateTime start, DateTime end);

  /// Rincian pemakaian seluler per UID/aplikasi dari NetworkStats Android.
  Future<AppUsageReading> readAppUsage(DateTime start, DateTime end);

  Future<UsageReading> refreshToday(DataPackage package);
}

/// Satu bucket statistik Android untuk satu UID.
class AppUsageBucket {
  final int uid;
  final String? packageName;
  final String? appName;
  final int rxBytes;
  final int txBytes;
  final DateTime start;
  final DateTime end;

  const AppUsageBucket({
    required this.uid,
    required this.packageName,
    required this.appName,
    required this.rxBytes,
    required this.txBytes,
    required this.start,
    required this.end,
  });

  int get totalBytes => rxBytes + txBytes;
}

class AppUsageReading {
  final UsageReadStatus status;
  final List<AppUsageBucket> buckets;
  final DateTime start;
  final DateTime end;
  final String? message;

  const AppUsageReading({
    required this.status,
    required this.buckets,
    required this.start,
    required this.end,
    required this.message,
  });
}

class UsageServiceImpl implements UsageService {
  static const MethodChannel _channel = MethodChannel('datawise/usage');

  UsageReading _reading(
    UsageReadStatus status,
    DateTime start,
    DateTime end, {
    int totalBytes = 0,
    String? message,
  }) {
    return UsageReading(
      status: status,
      totalBytes: totalBytes,
      start: start,
      end: end,
      message: message,
    );
  }

  UsageReadStatus _parseStatus(String? status) {
    switch (status) {
      case 'ok':
        return UsageReadStatus.ok;
      case 'permission_denied':
        return UsageReadStatus.permissionDenied;
      case 'unsupported':
        return UsageReadStatus.unsupported;
      default:
        return UsageReadStatus.error;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsagePermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openUsageAccessSettings() async {
    try {
      await _channel.invokeMethod('openUsageAccessSettings');
    } catch (_) {}
  }

  @override
  Future<void> openInternetSettings() async {
    try {
      await _channel.invokeMethod('openInternetSettings');
    } catch (_) {}
  }

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async {
    if (!end.isAfter(start)) {
      return _reading(
        UsageReadStatus.error,
        start,
        end,
        message: 'Rentang waktu tidak valid.',
      );
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getMobileUsage',
        {
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
        },
      );

      if (result == null) {
        return _reading(
          UsageReadStatus.error,
          start,
          end,
          message: 'Android tidak memberikan hasil pembacaan.',
        );
      }

      return _reading(
        _parseStatus(result['status'] as String?),
        start,
        end,
        totalBytes: (result['totalBytes'] as num?)?.toInt() ?? 0,
        message: result['message'] as String?,
      );
    } on PlatformException catch (e) {
      return _reading(
        UsageReadStatus.error,
        start,
        end,
        message: e.message ?? 'Terjadi kesalahan pada Android.',
      );
    } on MissingPluginException {
      return _reading(
        UsageReadStatus.unsupported,
        start,
        end,
        message: 'MethodChannel Usage belum tersedia.',
      );
    } catch (e) {
      return _reading(
        UsageReadStatus.error,
        start,
        end,
        message: 'Gagal membaca penggunaan data: $e',
      );
    }
  }

  @override
  Future<AppUsageReading> readAppUsage(DateTime start, DateTime end) async {
    if (!end.isAfter(start)) {
      return AppUsageReading(
        status: UsageReadStatus.error,
        buckets: const [],
        start: start,
        end: end,
        message: 'Rentang waktu tidak valid.',
      );
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getMobileUsageByApp',
        {
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
        },
      );

      if (result == null) {
        return AppUsageReading(
          status: UsageReadStatus.error,
          buckets: const [],
          start: start,
          end: end,
          message: 'Android tidak memberikan hasil pembacaan.',
        );
      }

      final rawBuckets = result['apps'] as List<dynamic>? ?? const [];
      final buckets = <AppUsageBucket>[];

      for (final item in rawBuckets) {
        if (item is! Map) continue;

        final rxBytes = (item['rxBytes'] as num?)?.toInt() ?? 0;
        final txBytes = (item['txBytes'] as num?)?.toInt() ?? 0;
        if (rxBytes + txBytes <= 0) continue;

        final bucketStart = (item['bucketStartMillis'] as num?)?.toInt() ?? 0;
        final bucketEnd = (item['bucketEndMillis'] as num?)?.toInt() ?? 0;

        buckets.add(
          AppUsageBucket(
            uid: (item['uid'] as num?)?.toInt() ?? -1,
            packageName: item['packageName'] as String?,
            appName: item['appName'] as String?,
            rxBytes: rxBytes,
            txBytes: txBytes,
            start: DateTime.fromMillisecondsSinceEpoch(bucketStart),
            end: DateTime.fromMillisecondsSinceEpoch(bucketEnd),
          ),
        );
      }

      return AppUsageReading(
        status: _parseStatus(result['status'] as String?),
        buckets: buckets,
        start: start,
        end: end,
        message: result['message'] as String?,
      );
    } on PlatformException catch (e) {
      return AppUsageReading(
        status: UsageReadStatus.error,
        buckets: const [],
        start: start,
        end: end,
        message: e.message ?? 'Terjadi kesalahan pada Android.',
      );
    } on MissingPluginException {
      return AppUsageReading(
        status: UsageReadStatus.unsupported,
        buckets: const [],
        start: start,
        end: end,
        message: 'MethodChannel Usage belum tersedia.',
      );
    } catch (e) {
      return AppUsageReading(
        status: UsageReadStatus.error,
        buckets: const [],
        start: start,
        end: end,
        message: 'Gagal membaca penggunaan per aplikasi: $e',
      );
    }
  }

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    final now = DateTime.now();
    final start = dateOnly(now);

    if (package.id == null) {
      return _reading(
        UsageReadStatus.error,
        start,
        now,
        message: 'Paket belum memiliki ID.',
      );
    }

    // Hasilnya tetap statistik agregat perangkat.
    // Penyimpanan ke usage_records dilakukan oleh UsageSyncService.
    return readMobileUsage(start, now);
  }
}
