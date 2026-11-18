import '../models/models.dart';

abstract class SettingsRepository {
  Future<UserSetting?> getByUserId(String userId);
  Future<void> upsert(UserSetting setting);
  Future<void> delete(String userId);
}
