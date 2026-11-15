abstract class SettingsRepository {
  Future<String?> get(String userId, String key);
  Future<void> set(String userId, String key, String value);
  Future<void> delete(String userId, String key);
}
