class UserSetting {
  final String userId, key, value;
  const UserSetting({required this.userId, required this.key, required this.value});
  Map<String, Object?> toMap() => {'user_id': userId, 'key': key, 'value': value};
  factory UserSetting.fromMap(Map<String, Object?> m) => UserSetting(
    userId: m['user_id'] as String, key: m['key'] as String,
    value: m['value'] as String,
  );
}
