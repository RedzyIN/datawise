import 'package:flutter/material.dart';

import '../models/models.dart';
import '../repositories/settings_repository.dart';

/// Pengaturan Light/Dark Mode milik Mawan, disimpan melalui kontrak
/// [SettingsRepository] SQLite dari develop (`user_settings`).
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._settingsRepository);

  final SettingsRepository _settingsRepository;

  ThemeMode _themeMode = ThemeMode.light;
  String? _currentUid;
  int _requestId = 0;

  ThemeMode get themeMode => _themeMode;

  Future<void> loadForUser(String? uid) async {
    if (_currentUid == uid) return;

    _currentUid = uid;
    final requestId = ++_requestId;

    if (uid == null) {
      _themeMode = ThemeMode.light;
      notifyListeners();
      return;
    }

    final setting = await _settingsRepository.getByUserId(uid);

    if (_currentUid != uid || requestId != _requestId) return;

    _themeMode =
        setting?.themeMode.toUpperCase() == 'DARK'
            ? ThemeMode.dark
            : ThemeMode.light;

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final requestId = ++_requestId;

    notifyListeners();

    final uid = _currentUid;
    if (uid == null) return;

    final existing = await _settingsRepository.getByUserId(uid);

    if (requestId != _requestId) return;

    await _settingsRepository.upsert(
      UserSetting(
        userId: uid,
        themeMode: mode == ThemeMode.dark ? 'DARK' : 'LIGHT',
        paletteKey: existing?.paletteKey ?? 'BLUE',
        notificationsEnabled: existing?.notificationsEnabled ?? true,
        timezoneId: existing?.timezoneId ?? 'UTC',
        updatedAt: DateTime.now(),
      ),
    );
  }
}
