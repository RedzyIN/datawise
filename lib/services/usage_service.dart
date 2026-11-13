import 'package:flutter/services.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';

abstract class UsageService {
  Future<bool> hasPermission();
  Future<void> openUsageAccessSettings();
  Future<void> openInternetSettings();
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end);
  Future<UsageReading> refreshToday(DataPackage package);
}

class UsageServiceImpl implements UsageService {
  UsageServiceImpl(this._usageRepo, this._settingsRepo);

  final UsageRepository _usageRepo;
  final SettingsRepository _settingsRepo;

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

    final reading = await readMobileUsage(start, now);

    if (reading.status != UsageReadStatus.ok) {
      return reading;
    }

    try {
      await _usageRepo.upsertRecord(
        package.id!,
        start,
        reading.totalBytes,
        UsageSource.auto,
      );

      await _settingsRepo.set('last_usage_refresh', timeToMs(now).toString());

      return reading;
    } catch (e) {
      return _reading(
        UsageReadStatus.error,
        start,
        now,
        message: 'Gagal menyimpan penggunaan data: $e',
      );
    }
  }
}
