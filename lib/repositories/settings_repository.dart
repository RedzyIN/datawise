// MILIK ARSITEK. KONTRAK BEKU #4.
// Kunci yang dibekukan: notif_enabled ('1'/'0'), last_usage_refresh (ms UTC).

abstract class SettingsRepository {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
