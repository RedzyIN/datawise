import '../models/models.dart';

abstract class SettingsRepository {
  Future<UserSetting?> getByUserId(String userId);
  Future<void> upsert(UserSetting setting);

  /// Memperbarui preferensi notifikasi tanpa menyentuh preferensi lain.
  ///
  /// ThemeProvider dan SettingsProvider menyimpan pada baris yang sama
  /// (`user_settings`). Penulisan selektif ini mencegah salah satu fitur
  /// menimpa mode tema atau palet milik fitur lainnya.
  Future<void> updateNotifications(
    String userId, {
    required bool enabled,
    required DateTime updatedAt,
  });
  Future<void> delete(String userId);
}
