import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/core/theme_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';

UserSetting _setting({
  required String userId,
  String themeMode = 'LIGHT',
  String paletteKey = 'TEAL',
  bool notificationsEnabled = true,
}) {
  return UserSetting(
    userId: userId,
    themeMode: themeMode,
    paletteKey: paletteKey,
    notificationsEnabled: notificationsEnabled,
    timezoneId: 'Asia/Jakarta',
    updatedAt: DateTime(2026, 11, 25, 8),
  );
}

void main() {
  late InMemorySettingsRepository repository;
  late ThemeProvider provider;

  setUp(() {
    repository = InMemorySettingsRepository();
    provider = ThemeProvider(repository);
  });

  test('nilai bawaan adalah Light Mode dan palet teal', () {
    expect(provider.themeMode, ThemeMode.light);
    expect(provider.paletteKey, 'TEAL');
    expect(provider.palette.key, 'TEAL');
  });

  test('perubahan Light/Dark Mode tersimpan untuk pengguna aktif', () async {
    await provider.loadForUser('u1');

    await provider.setThemeMode(ThemeMode.dark);

    expect(provider.themeMode, ThemeMode.dark);
    expect(repository.items['u1']?.themeMode, 'DARK');

    // Pengaturan lain tidak ikut berubah saat mode tema disimpan.
    expect(repository.items['u1']?.timezoneId, 'UTC');
  });

  test('pilihan palet tersimpan bersama mode tema', () async {
    await provider.loadForUser('u1');
    await provider.setThemeMode(ThemeMode.dark);

    await provider.setPalette('RED_ACCENT');

    expect(provider.paletteKey, 'RED_ACCENT');
    expect(repository.items['u1']?.paletteKey, 'RED_ACCENT');
    expect(repository.items['u1']?.themeMode, 'DARK');
  });

  test('palet tidak dikenal diabaikan', () async {
    await provider.loadForUser('u1');

    await provider.setPalette('BUKAN_PALET');

    expect(provider.paletteKey, 'TEAL');
    expect(repository.items['u1'], isNull);
  });

  test('pengaturan setiap akun terisolasi', () async {
    await repository.upsert(_setting(userId: 'u1'));

    await provider.loadForUser('u1');
    await provider.setThemeMode(ThemeMode.dark);
    await provider.setPalette('YELLOW_GLOW');

    await repository.upsert(_setting(userId: 'u2'));

    await provider.loadForUser('u2');

    expect(provider.themeMode, ThemeMode.light);
    expect(provider.paletteKey, 'TEAL');

    // Kembali ke akun pertama memakai pengaturannya sendiri.
    await provider.loadForUser('u1');

    expect(provider.themeMode, ThemeMode.dark);
    expect(provider.paletteKey, 'YELLOW_GLOW');
  });

  test(
    'logout mengembalikan tampilan ke bawaan tanpa menghapus data',
    () async {
      await provider.loadForUser('u1');
      await provider.setThemeMode(ThemeMode.dark);
      await provider.setPalette('NEUTRAL');

      await provider.loadForUser(null);

      expect(provider.themeMode, ThemeMode.light);
      expect(provider.paletteKey, 'TEAL');

      // Preferensi akun tetap tersimpan di database.
      expect(repository.items['u1']?.themeMode, 'DARK');
      expect(repository.items['u1']?.paletteKey, 'NEUTRAL');
    },
  );

  test('nilai palet lama BLUE tampil sebagai teal', () async {
    await repository.upsert(_setting(userId: 'u1', paletteKey: 'BLUE'));

    await provider.loadForUser('u1');

    expect(provider.palette.key, 'TEAL');
  });

  test(
    'mode tema tersimpan dan terbaca kembali setelah aplikasi dibuka ulang',
    () async {
      await provider.loadForUser('u1');
      await provider.setThemeMode(ThemeMode.dark);

      // Provider baru mensimulasikan aplikasi yang dibuka kembali.
      final reopened = ThemeProvider(repository);
      await reopened.loadForUser('u1');

      expect(reopened.themeMode, ThemeMode.dark);
    },
  );
}
