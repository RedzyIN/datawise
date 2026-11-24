// Provider riwayat Smart Alerts.
//
// UI -> AlertProvider -> AlertRepository / PackageRepository -> SQLite.
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/alert_repository.dart';
import '../../repositories/package_repository.dart';

enum AlertHistoryLoad { idle, loading, ready, error }

/// Satu baris riwayat alert beserta nama paket terkait.
class AlertHistoryEntry {
  const AlertHistoryEntry({required this.alert, required this.packageName});

  final AlertLog alert;
  final String? packageName;
}

class AlertProvider extends ChangeNotifier {
  AlertProvider(this._alertRepo, this._packageRepo);

  final AlertRepository _alertRepo;
  final PackageRepository _packageRepo;

  AlertHistoryLoad loadState = AlertHistoryLoad.idle;
  List<AlertHistoryEntry> entries = const [];
  String? errorMessage;

  int get unreadCount => entries.where((entry) => !entry.alert.isRead).length;

  bool get isEmpty => entries.isEmpty;

  Future<void> load(String userId) async {
    loadState = AlertHistoryLoad.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final packages = await _packageRepo.getAll(userId);

      final names = <String, String>{
        for (final package in packages)
          if (package.id != null) package.id!: package.packageName,
      };

      final loaded = <AlertHistoryEntry>[];

      for (final package in packages) {
        final packageId = package.id;
        if (packageId == null) continue;

        final alerts = await _alertRepo.getByPackage(packageId);

        for (final alert in alerts) {
          loaded.add(
            AlertHistoryEntry(
              alert: alert,
              packageName: names[alert.packageId],
            ),
          );
        }
      }

      // Terbaru lebih dulu.
      loaded.sort((a, b) => b.alert.triggeredAt.compareTo(a.alert.triggeredAt));

      entries = loaded;
      loadState = AlertHistoryLoad.ready;
    } on AppException catch (error) {
      errorMessage = error.message;
      loadState = AlertHistoryLoad.error;
    } catch (_) {
      errorMessage = 'Gagal memuat riwayat notifikasi.';
      loadState = AlertHistoryLoad.error;
    }

    notifyListeners();
  }

  Future<void> refresh(String userId) => load(userId);

  /// Menandai satu alert sebagai sudah dibaca.
  Future<bool> markRead(String alertId) async {
    try {
      await _alertRepo.markRead(alertId);

      entries = [
        for (final entry in entries)
          entry.alert.id == alertId
              ? AlertHistoryEntry(
                  alert: _copyRead(entry.alert),
                  packageName: entry.packageName,
                )
              : entry,
      ];

      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Menandai seluruh alert milik satu paket sebagai sudah dibaca.
  Future<bool> markAllReadForPackage(String packageId) async {
    try {
      await _alertRepo.markAllRead(packageId);

      entries = [
        for (final entry in entries)
          entry.alert.packageId == packageId
              ? AlertHistoryEntry(
                  alert: _copyRead(entry.alert),
                  packageName: entry.packageName,
                )
              : entry,
      ];

      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Menandai semua alert yang tampil sebagai sudah dibaca, dikelompokkan per
  /// paket agar repository tetap menerima operasi per paket.
  Future<bool> markAllRead() async {
    final packageIds = <String>{
      for (final entry in entries)
        if (!entry.alert.isRead) entry.alert.packageId,
    };

    var success = true;

    for (final packageId in packageIds) {
      success = await markAllReadForPackage(packageId) && success;
    }

    return success;
  }

  AlertLog _copyRead(AlertLog alert) {
    return AlertLog(
      id: alert.id,
      packageId: alert.packageId,
      quotaCategoryId: alert.quotaCategoryId,
      alertType: alert.alertType,
      message: alert.message,
      observedBytes: alert.observedBytes,
      thresholdBytes: alert.thresholdBytes,
      dedupeKey: alert.dedupeKey,
      triggeredAt: alert.triggeredAt,
      isRead: true,
    );
  }
}
