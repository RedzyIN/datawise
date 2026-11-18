// PEMILIK: Anggota D (Nero). KONTRAK BEKU #4 & #6.
// Aturan pemicu (dokumen Arsitek / KONFLIK_ANTAR_DOKUMEN):
//  - daily80   : pemakaian hari ini 80% s.d. <100% dari target harian
//  - daily100  : 100% s.d. 100,5%
//  - dailyOver : > 100,5%
//  - quota10   : sisa kuota <= 10% dari total; alert_date = end_date paket
//  - expiring1d: hari ini = end_date - 1 hari
// Satu hari hanya mengirim SATU peringatan harian (tingkat tertinggi). Setiap peringatan
// punya kunci dedupe (paket, jenis, tanggal) lewat AlertRepository. Hanya notifikasi;
// aplikasi tidak memutus koneksi data.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/constants.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';

abstract class AlertService {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> evaluateAndNotify(DataPackage package, PlannerResult result);
}

/// Pemisah antara aturan peringatan dan plugin notifikasi (agar mudah diuji).
abstract class NotificationSink {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> show(int id, String title, String body);
}

class LocalNotificationSink implements NotificationSink {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'datawise_alerts';
  static const _channelName = 'Peringatan kuota';

  @override
  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Peringatan target harian, sisa kuota, dan masa aktif paket',
          importance: Importance.high,
        ));
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> show(int id, String title, String body) => _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
}

class AlertServiceImpl implements AlertService {
  AlertServiceImpl(
    this._alertRepo,
    this._settingsRepo, {
    NotificationSink? sink,
    DateTime Function()? now,
  })  : _sink = sink ?? LocalNotificationSink(),
        _now = now ?? DateTime.now;

  final AlertRepository _alertRepo;
  final SettingsRepository _settingsRepo;
  final NotificationSink _sink;
  final DateTime Function() _now;

  Future<void>? _initFuture;

  @override
  Future<void> init() => _initFuture ??= _sink.init();

  @override
  Future<bool> requestPermission() async {
    await init();
    return _sink.requestPermission();
  }

  Future<bool> _enabled() async {
    // Default aktif; hanya '0' yang mematikan.
    return await _settingsRepo.get(AppConstants.keyNotifEnabled) != '0';
  }

  @override
  Future<void> evaluateAndNotify(DataPackage package, PlannerResult result) async {
    final packageId = package.id;
    if (packageId == null) return;
    if (!await _enabled()) return;
    if (result.status == PlannerStatus.expired ||
        result.status == PlannerStatus.notStarted) {
      return;
    }

    final today = dateOnly(_now());
    final candidates = <(AlertType, DateTime, String, String)>[];

    // Peringatan harian: hanya tingkat tertinggi.
    final pct = result.todayPercentOfTarget;
    if (pct != null) {
      if (pct > 100.5) {
        candidates.add((
          AlertType.dailyOver,
          today,
          'Target harian terlampaui',
          'Pemakaian hari ini melewati target harian ${package.name}.'
        ));
      } else if (pct >= 100) {
        candidates.add((
          AlertType.daily100,
          today,
          'Target harian tercapai',
          'Pemakaian hari ini sudah mencapai target harian ${package.name}.'
        ));
      } else if (pct >= 80) {
        candidates.add((
          AlertType.daily80,
          today,
          'Mendekati target harian',
          'Pemakaian hari ini sudah 80% dari target harian ${package.name}.'
        ));
      }
    }

    // Sisa kuota <= 10% (integer math agar tidak ada galat desimal).
    if (result.totalBytes > 0 && result.remainingBytes * 100 <= result.totalBytes * 10) {
      candidates.add((
        AlertType.quota10,
        dateOnly(package.endDate),
        'Sisa kuota menipis',
        'Sisa kuota ${package.name} tinggal 10% atau kurang.'
      ));
    }

    // Paket berakhir besok.
    if (today == dateOnly(package.endDate).subtract(const Duration(days: 1))) {
      candidates.add((
        AlertType.expiring1d,
        today,
        'Paket berakhir besok',
        '${package.name} akan berakhir besok.'
      ));
    }

    if (candidates.isEmpty) return;
    await init();

    for (final c in candidates) {
      final (type, date, title, body) = c;
      if (await _alertRepo.hasBeenSent(packageId, type, date)) continue;
      try {
        await _sink.show(packageId * 10 + type.index, title, body);
        await _alertRepo.markSent(packageId, type, date);
      } catch (_) {
        // Gagal menampilkan notifikasi: jangan tandai terkirim agar dicoba lagi.
      }
    }
  }
}
