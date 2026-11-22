
import 'package:flutter/material.dart';

import '../repositories/settings_repository.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._settingsRepository);

  final SettingsRepository _settingsRepository;

  ThemeMode _themeMode = ThemeMode.light;
  String? _currentUid;
  int _requestId = 0;

  ThemeMode get themeMode => _themeMode;

  String _themeKey(String uid) => 'theme_mode_$uid';

  Future<void> loadForUser(String? uid) async {
    if (_currentUid == uid) return;

    _currentUid = uid;
    final requestId = ++_requestId;

    if (uid == null) {
      _themeMode = ThemeMode.light;
      notifyListeners();
      return;
    }

    final savedTheme = await _settingsRepository.get(_themeKey(uid));

    if (_currentUid != uid || requestId != _requestId) return;

    _themeMode =
        savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final requestId = ++_requestId;

    notifyListeners();

    final uid = _currentUid;
    if (uid == null) return;

    await _settingsRepository.set(
      _themeKey(uid),
      mode == ThemeMode.dark ? 'dark' : 'light',
    );

    if (requestId != _requestId) return;
  }
}
