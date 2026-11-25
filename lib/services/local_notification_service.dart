// Satu-satunya infrastruktur notifikasi lokal DATAWISE
// (flutter_local_notifications).
//
// Dipakai bersama oleh Data Limit Warning (`showWarning`) dan Smart Alerts
// (`showAlert`). Keduanya berbagi satu instance plugin, satu inisialisasi, dan
// satu alur izin POST_NOTIFICATIONS, tetapi tetap memakai channel Android yang
// berbeda agar pengguna dapat mengatur keduanya secara terpisah.
//
// Setiap metode pengiriman mengembalikan `true` bila notifikasi berada di
// notification shade (baru dikirim, atau sudah dikirim pada proses ini).
// Pemanggil sengaja TIDAK mengulang pengiriman ketika hasilnya `false`:
// AlertLog yang sudah tercatat adalah penanda "sudah diberitahukan hari ini",
// sehingga kegagalan sesaat tidak boleh memunculkan notifikasi berulang.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract class LocalNotificationService {
  Future<bool> init();

  Future<bool> requestPermission();

  Future<bool> showWarning({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  Future<bool> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
  });
}

class FlutterLocalNotificationService implements LocalNotificationService {
  FlutterLocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String warningChannelId = 'data_limit_warning';
  static const String warningChannelName = 'Peringatan Batas Data';
  static const String warningChannelDescription =
      'Peringatan pemakaian data harian DATAWISE.';

  static const String alertChannelId = 'datawise_alerts';
  static const String alertChannelName = 'Peringatan kuota';
  static const String alertChannelDescription =
      'Peringatan target, sisa kuota, dan masa aktif paket.';

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _initialization;

  /// Id notifikasi yang sudah dikirim pada proses aplikasi ini.
  ///
  /// Deduplikasi AlertLog saja tidak cukup: bila baris riwayat terhapus atau
  /// beberapa jalur evaluasi berjalan hampir bersamaan, notifikasi dengan
  /// id yang sama tidak boleh ditampilkan dua kali. Id berasal dari kunci
  /// deduplikasi (paket + jenis + tanggal lokal), jadi kejadian baru tetap
  /// mendapat id baru dan tetap tampil.
  final Set<int> _delivered = <int>{};

  @override
  Future<bool> init() => _initialization ??= _init();

  Future<bool> _init() async {
    // Plugin tidak tersedia di web/desktop; alert tetap disimpan sebagai
    // riwayat tanpa menghentikan alur aplikasi.
    if (kIsWeb) return false;

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          warningChannelId,
          warningChannelName,
          description: warningChannelDescription,
          importance: Importance.high,
        ),
      );

      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          alertChannelId,
          alertChannelName,
          description: alertChannelDescription,
          importance: Importance.high,
        ),
      );

      // Android 13+ meminta izin POST_NOTIFICATIONS saat runtime. Penolakan
      // tidak boleh menghentikan aplikasi.
      try {
        await android?.requestNotificationsPermission();
      } catch (_) {
        // Izin ditolak atau tidak tersedia; aplikasi tetap berjalan.
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    await init();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) return false;

    try {
      return await android.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> showWarning({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) {
    return _show(
      channelId: warningChannelId,
      channelName: warningChannelName,
      channelDescription: warningChannelDescription,
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
  }

  @override
  Future<bool> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) {
    return _show(
      channelId: alertChannelId,
      channelName: alertChannelName,
      channelDescription: alertChannelDescription,
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<bool> _show({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!await init()) return false;

    // Sudah dikirim pada proses ini: jangan tampilkan ulang, termasuk setelah
    // pengguna menggeser notifikasi tersebut dari notification shade.
    if (_delivered.contains(id)) return true;

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );

      _delivered.add(id);
      return true;
    } catch (error) {
      // Kegagalan tidak diulang oleh pemanggil, jadi catat agar tetap dapat
      // didiagnosis saat pengujian perangkat.
      debugPrint('Notifikasi lokal gagal ditampilkan: $error');
      return false;
    }
  }
}
