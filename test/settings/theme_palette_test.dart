import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/models/theme_palette.dart';

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = math.max(first, second);
  final darker = math.min(first, second);

  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('ThemePalette', () {
    test('setiap palet memiliki konfigurasi Light dan Dark', () {
      expect(ThemePalette.available, isNotEmpty);

      for (final palette in ThemePalette.available) {
        expect(palette.key.trim(), isNotEmpty);
        expect(palette.name.trim(), isNotEmpty);
        expect(palette.description.trim(), isNotEmpty);

        // Light selalu berlatar lebih terang daripada Dark.
        expect(
          palette.light.background.computeLuminance(),
          greaterThan(palette.dark.background.computeLuminance()),
          reason: '${palette.name} harus membedakan Light dan Dark',
        );

        // Tidak hanya background yang berubah: warna identitas juga berbeda.
        expect(
          palette.light.primary,
          isNot(palette.dark.primary),
          reason: '${palette.name} membutuhkan primary khusus per mode',
        );
      }
    });

    test('key palet unik', () {
      final keys = ThemePalette.available.map((p) => p.key).toList();

      expect(keys.toSet().length, keys.length);
    });

    test('teks tetap terbaca pada background setiap palet', () {
      for (final palette in ThemePalette.available) {
        expect(
          _contrast(palette.light.text, palette.light.background),
          greaterThanOrEqualTo(4.5),
          reason: 'Kontras teks Light ${palette.name} terlalu rendah',
        );

        expect(
          _contrast(palette.dark.text, palette.dark.background),
          greaterThanOrEqualTo(4.5),
          reason: 'Kontras teks Dark ${palette.name} terlalu rendah',
        );

        // Teks pada kartu juga harus terbaca, bukan hanya di background.
        expect(
          _contrast(palette.light.text, palette.light.surface),
          greaterThanOrEqualTo(4.5),
          reason:
              'Kontras teks pada kartu Light ${palette.name} terlalu rendah',
        );

        expect(
          _contrast(palette.dark.text, palette.dark.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Kontras teks pada kartu Dark ${palette.name} terlalu rendah',
        );
      }
    });

    test('palet bawaan adalah identitas teal', () {
      expect(ThemePalette.defaultPalette.key, 'TEAL');
      expect(ThemePalette.available.first.key, 'TEAL');
    });

    test('key lama dipetakan ke palet yang tersedia', () {
      expect(ThemePalette.fromKey('BLUE').key, 'TEAL');
      expect(ThemePalette.fromKey('OCEAN').key, 'TEAL');
      expect(ThemePalette.fromKey('PURPLE').key, 'TEAL');
      expect(ThemePalette.fromKey('ORANGE').key, 'YELLOW_GLOW');
      expect(ThemePalette.fromKey('RED').key, 'RED_ACCENT');
      expect(ThemePalette.fromKey('grey').key, 'NEUTRAL');
    });

    test('key kosong atau tidak dikenal memakai palet bawaan', () {
      expect(ThemePalette.fromKey(null).key, 'TEAL');
      expect(ThemePalette.fromKey('').key, 'TEAL');
      expect(ThemePalette.fromKey('TIDAK_ADA').key, 'TEAL');
      expect(ThemePalette.fromKey('red_accent').key, 'RED_ACCENT');
    });
  });
}
