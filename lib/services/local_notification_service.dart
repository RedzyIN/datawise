// Notifikasi lokal DATAWISE (flutter_local_notifications).
// Dipakai Data Limit Warning; dapat dipakai ulang oleh fitur alert lain.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract class LocalNotificationService {
  Future<void> showWarning({
    required int id,
    required String title,
    required String body,
    String? payload,
  });
}

class FlutterLocalNotificationService implements LocalNotificationService {
  FlutterLocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String _channelId = 'data_limit_warning';
  static const String _channelName = 'Peringatan Batas Data';
  static const String _channelDescription =
      'Peringatan pemakaian data harian DATAWISE.';

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initialization;

  Future<void> _ensureInitialized() => _initialization ??= _init();

  Future<void> _init() async {
    if (kIsWeb) return;

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      // Android 13+ meminta izin POST_NOTIFICATIONS saat runtime.
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Notifikasi lokal tidak tersedia pada platform ini (mis. pengujian
      // desktop atau plugin belum siap). Peringatan tetap tersimpan sebagai
      // AlertLog tanpa menghentikan alur aplikasi.
    }
  }

  @override
  Future<void> showWarning({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _ensureInitialized();

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {
      // Kegagalan menampilkan notifikasi tidak boleh menggagalkan evaluasi.
    }
  }
}
