import 'package:flutter/material.dart';

/// Model warna untuk satu mode tampilan.
class ThemePaletteColors {
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color text;

  const ThemePaletteColors({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.text,
  });
}

/// Model satu palet yang memiliki konfigurasi Light dan Dark.
class ThemePalette {
  final String key;
  final String name;
  final ThemePaletteColors light;
  final ThemePaletteColors dark;

  const ThemePalette({
    required this.key,
    required this.name,
    required this.light,
    required this.dark,
  });

  /// Semua pilihan palet yang tersedia di DATAWISE.
  static const List<ThemePalette> available = [
    ThemePalette(
      key: 'TEAL',
      name: 'Teal',
      light: ThemePaletteColors(
        primary: Color(0xFF00796F),
        secondary: Color(0xFF00695C),
        accent: Color(0xFF26A69A),
        background: Color(0xFFE4FBF7),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF073B3A),
      ),
      dark: ThemePaletteColors(
        primary: Color(0xFF31C9B8),
        secondary: Color(0xFF5AE38C),
        accent: Color(0xFF2BB7A8),
        background: Color(0xFF0E1513),
        surface: Color(0xFF16201E),
        text: Color(0xFFF2F7F6),
      ),
    ),
    ThemePalette(
      key: 'OCEAN',
      name: 'Blue',
      light: ThemePaletteColors(
        primary: Color(0xFF1565C0),
        secondary: Color(0xFF0D47A1),
        accent: Color(0xFF42A5F5),
        background: Color(0xFFEAF3FF),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF102A43),
      ),
      dark: ThemePaletteColors(
        primary: Color(0xFF64B5F6),
        secondary: Color(0xFF90CAF9),
        accent: Color(0xFF42A5F5),
        background: Color(0xFF101B2D),
        surface: Color(0xFF1A2940),
        text: Color(0xFFF1F6FD),
      ),
    ),
    ThemePalette(
      key: 'PURPLE',
      name: 'Purple',
      light: ThemePaletteColors(
        primary: Color(0xFF7B1FA2),
        secondary: Color(0xFF6A1B9A),
        accent: Color(0xFFAB47BC),
        background: Color(0xFFF6ECFA),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF32143D),
      ),
      dark: ThemePaletteColors(
        primary: Color(0xFFCE93D8),
        secondary: Color(0xFFE1BEE7),
        accent: Color(0xFFBA68C8),
        background: Color(0xFF211329),
        surface: Color(0xFF30203A),
        text: Color(0xFFF8F0FA),
      ),
    ),
    ThemePalette(
      key: 'ORANGE',
      name: 'Orange',
      light: ThemePaletteColors(
        primary: Color(0xFFEF6C00),
        secondary: Color(0xFFE65100),
        accent: Color(0xFFFFA726),
        background: Color(0xFFFFF3E6),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF40230F),
      ),
      dark: ThemePaletteColors(
        primary: Color(0xFFFFB74D),
        secondary: Color(0xFFFFCC80),
        accent: Color(0xFFFF9800),
        background: Color(0xFF24180F),
        surface: Color(0xFF352519),
        text: Color(0xFFFFF5EA),
      ),
    ),
  ];

  /// Palet bawaan DATAWISE.
  static ThemePalette get defaultPalette => available.first;

  /// Mengambil palet berdasarkan key dari database.
  ///
  /// BLUE adalah nilai default lama di database. Nilai tersebut
  /// dipetakan ke Teal agar tampilan pengguna lama tidak berubah.
  static ThemePalette fromKey(String? key) {
    if (key == null || key.isEmpty || key.toUpperCase() == 'BLUE') {
      return defaultPalette;
    }

    for (final palette in available) {
      if (palette.key == key.toUpperCase()) {
        return palette;
      }
    }

    return defaultPalette;
  }
}
