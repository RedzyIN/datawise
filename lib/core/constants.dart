// MILIK ARSITEK.

const int kBytesPerGB = 1000000000; // desimal, sama seperti operator
const int kBytesPerMB = 1000000;

class AppConstants {
  static const String appName = 'DATAWISE';
  static const String appVersion = '1.0.0';
  static const String dbName = 'datawise.db';
  static const int dbVersion = 1;

  // Kunci app_settings yang dibekukan
  static const String keyNotifEnabled = 'notif_enabled'; // '1' / '0'
  static const String keyLastUsageRefresh = 'last_usage_refresh'; // ms UTC
}
