import 'date_codec.dart';

class UserSetting {
  final String userId;
  final String themeMode;
  final String paletteKey;
  final bool notificationsEnabled;
  final String timezoneId;
  final DateTime updatedAt;

  const UserSetting({
    required this.userId,
    required this.themeMode,
    required this.paletteKey,
    required this.notificationsEnabled,
    required this.timezoneId,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'user_id': userId,
    'theme_mode': themeMode,
    'palette_key': paletteKey,
    'notifications_enabled': notificationsEnabled ? 1 : 0,
    'timezone_id': timezoneId,
    'updated_at': timeToIso(updatedAt),
  };

  factory UserSetting.fromMap(Map<String, Object?> map) => UserSetting(
    userId: map['user_id'] as String,
    themeMode: map['theme_mode'] as String,
    paletteKey: map['palette_key'] as String,
    notificationsEnabled: (map['notifications_enabled'] as int) == 1,
    timezoneId: map['timezone_id'] as String,
    updatedAt: timeFromIso(map['updated_at'] as String),
  );
}
