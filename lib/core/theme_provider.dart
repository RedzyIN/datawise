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

  /// Default Light Theme develop bila pengguna belum punya preferensi.
  Future<void> loadForUser(String? uid) async {
    if (_currentUid == uid) return;

    _currentUid = uid;
    final requestId = ++_requestId;

    if (uid == null) {
      _themeMode = ThemeMode.light;
      notifyListeners();
      return;
    }

    final setting = await _readSetting(uid);

    if (_currentUid != uid || requestId != _requestId) return;

    _themeMode = setting?.themeMode.toUpperCase() == 'DARK'
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

    final existing = await _readSetting(uid);

    if (requestId != _requestId) return;

    try {
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
    } catch (error, stack) {
      // Preferensi gagal disimpan (mis. SQLite bermasalah). Tema tetap
      // diterapkan untuk sesi ini, dan penyebabnya dicatat untuk developer.
      debugPrint('[DATAWISE theme] gagal menyimpan preferensi tema: $error');
      debugPrintStack(stackTrace: stack, label: '[DATAWISE theme]');
    }
  }

  Future<UserSetting?> _readSetting(String uid) async {
    try {
      return await _settingsRepository.getByUserId(uid);
    } catch (error, stack) {
      debugPrint('[DATAWISE theme] gagal membaca preferensi tema: $error');
      debugPrintStack(stackTrace: stack, label: '[DATAWISE theme]');
      return null;
    }
  }
}
