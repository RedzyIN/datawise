import 'package:flutter/material.dart';

import '../models/models.dart';
import '../repositories/settings_repository.dart';

/// Mengatur mode tampilan dan pilihan palet warna DATAWISE.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._settingsRepository);

  final SettingsRepository _settingsRepository;

  ThemeMode _themeMode = ThemeMode.light;

  // BLUE merupakan nilai default lama pada database.
  // ThemePalette.fromKey memetakannya ke Teal.
  String _paletteKey = 'BLUE';

  String? _currentUid;
  int _requestId = 0;

  // Mengantrekan penyimpanan agar perubahan tidak saling menimpa.
  Future<void> _saveQueue = Future<void>.value();

  ThemeMode get themeMode => _themeMode;

  String get paletteKey => _paletteKey;

  ThemePalette get palette => ThemePalette.fromKey(_paletteKey);

  /// Memuat pengaturan berdasarkan akun yang sedang login.
  Future<void> loadForUser(String? uid) async {
    if (_currentUid == uid) return;

    _currentUid = uid;
    final requestId = ++_requestId;

    if (uid == null) {
      _themeMode = ThemeMode.light;
      _paletteKey = 'BLUE';
      notifyListeners();
      return;
    }

    _themeMode = ThemeMode.light;
    _paletteKey = 'BLUE';
    notifyListeners();

    final setting = await _readSetting(uid);

    if (_currentUid != uid || requestId != _requestId) return;

    _themeMode = setting?.themeMode.toUpperCase() == 'DARK'
        ? ThemeMode.dark
        : ThemeMode.light;

    _paletteKey = setting?.paletteKey ?? 'BLUE';

    notifyListeners();
  }

  /// Mengganti Light atau Dark Mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    await _persistPreferences();
  }

  /// Mengganti palet warna.
  Future<void> setPalette(String key) async {
    ThemePalette? selectedPalette;

    for (final item in ThemePalette.available) {
      if (item.key == key.toUpperCase()) {
        selectedPalette = item;
        break;
      }
    }

    if (selectedPalette == null) return;

    _paletteKey = selectedPalette.key;
    notifyListeners();

    await _persistPreferences();
  }

  /// Menyimpan mode dan palet tanpa menghapus pengaturan lainnya.
  Future<void> _persistPreferences() {
    final uid = _currentUid;

    if (uid == null) return Future<void>.value();

    _saveQueue = _saveQueue
        .then((_) async {
          if (_currentUid != uid) return;

          final existing = await _readSetting(uid);

          if (_currentUid != uid) return;

          await _settingsRepository.upsert(
            UserSetting(
              userId: uid,
              themeMode: _themeMode == ThemeMode.dark ? 'DARK' : 'LIGHT',
              paletteKey: _paletteKey,
              notificationsEnabled: existing?.notificationsEnabled ?? true,
              timezoneId: existing?.timezoneId ?? 'UTC',
              updatedAt: DateTime.now(),
            ),
          );
        })
        .catchError((Object error, StackTrace stack) {
          debugPrint('[DATAWISE theme] gagal menyimpan pengaturan: $error');
          debugPrintStack(stackTrace: stack, label: '[DATAWISE theme]');
        });

    return _saveQueue;
  }

  Future<UserSetting?> _readSetting(String uid) async {
    try {
      return await _settingsRepository.getByUserId(uid);
    } catch (error, stack) {
      debugPrint('[DATAWISE theme] gagal membaca pengaturan: $error');
      debugPrintStack(stackTrace: stack, label: '[DATAWISE theme]');
      return null;
    }
  }
}
