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
///
/// Identitas DATAWISE adalah teal. Palet alternatif tetap memakai teal sebagai
/// warna identitas atau aksen, bukan menggantinya dengan biru/ungu.
class ThemePalette {
  final String key;
  final String name;
  final String description;
  final ThemePaletteColors light;
  final ThemePaletteColors dark;

  const ThemePalette({
    required this.key,
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
  });

  /// Semua pilihan palet yang tersedia di DATAWISE.
  static const List<ThemePalette> available = [
    // Palet bawaan: teal di atas off-white (light) dan charcoal (dark).
    ThemePalette(
      key: 'TEAL',
      name: 'Teal Default',
      description: 'Teal dengan latar off-white dan charcoal',
      light: ThemePaletteColors(
        primary: Color(0xFF00796F),
        secondary: Color(0xFF00695C),
        accent: Color(0xFF26A69A),
        background: Color(0xFFEAF9F6),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF073B3A),
      ),
      dark: ThemePaletteColors(
        primary: Color(0xFF31C9B8),
        secondary: Color(0xFF2BB7A8),
        accent: Color(0xFF2BB7A8),
        background: Color(0xFF0E1513),
        surface: Color(0xFF16201E),
        text: Color(0xFFF2F7F6),
      ),
    ),
    // Aksen merah: putih dengan merah (light), charcoal gelap (dark).
    ThemePalette(
      key: 'RED_ACCENT',
      name: 'Red Accent',
      description: 'Putih dan merah dengan aksen teal',
      light: ThemePaletteColors(
        primary: Color(0xFFC62828),
        secondary: Color(0xFF8E2020),
        accent: Color(0xFF00796F),
        background: Color(0xFFFFF7F6),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF3A0B0B),
      ),
      dark: ThemePaletteColors(
        primary: Color(0xFFFF8A80),
        secondary: Color(0xFFFFB4A8),
        accent: Color(0xFF31C9B8),
        background: Color(0xFF14100F),
        surface: Color(0xFF231817),
        text: Color(0xFFF7F0EF),
      ),
    ),
    // Aksen kuning pucat: teal dengan glow kuning (light), hitam (dark).
    ThemePalette(
      key: 'YELLOW_GLOW',
      name: 'Yellow Glow',
      description: 'Teal dengan aksen kuning pucat yang menyala',
      light: ThemePaletteColors(
        primary: Color(0xFF00796F),
        secondary: Color(0xFF00695C),
        accent: Color(0xFFF2C94C),
        background: Color(0xFFFFFDF5),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF073B3A),
      ),
      dark: ThemePaletteColors(
        primary: Color(0xFFFFE066),
        secondary: Color(0xFFFFD54F),
        accent: Color(0xFFF2C94C),
        background: Color(0xFF070A09),
        surface: Color(0xFF141B18),
        text: Color(0xFFF7F9F6),
      ),
    ),
    // Netral: putih dan abu-abu (light), hitam dan abu-abu (dark).
    ThemePalette(
      key: 'NEUTRAL',
      name: 'Neutral',
      description: 'Putih dan abu-abu tanpa warna aksen mencolok',
      light: ThemePaletteColors(
        primary: Color(0xFF37474F),
        secondary: Color(0xFF263238),
        accent: Color(0xFF90A4AE),
        background: Color(0xFFF7F8F8),
        surface: Color(0xFFFFFFFF),
        text: Color(0xFF1B2321),
      ),
      dark: ThemePaletteColors(
        primary: Color(0xFFB0BEC5),
        secondary: Color(0xFFCFD8DC),
        accent: Color(0xFF78909C),
        background: Color(0xFF0B0C0C),
        surface: Color(0xFF171A19),
        text: Color(0xFFF2F5F4),
      ),
    ),
  ];

  /// Palet bawaan DATAWISE (identitas teal).
  static ThemePalette get defaultPalette => available.first;

  /// Key lama yang pernah tersimpan di `user_settings.palette_key`.
  ///
  /// Biru dan ungu tidak lagi menjadi identitas DATAWISE, jadi keduanya
  /// dipetakan ke palet teal agar pengguna lama tidak melihat tema yang tidak
  /// dikenal. Pemetaan hanya membaca; nilai database tidak diubah paksa.
  static const Map<String, String> _legacyKeys = {
    'BLUE': 'TEAL',
    'OCEAN': 'TEAL',
    'PURPLE': 'TEAL',
    'ORANGE': 'YELLOW_GLOW',
    'AMBER': 'YELLOW_GLOW',
    'YELLOW': 'YELLOW_GLOW',
    'RED': 'RED_ACCENT',
    'GREY': 'NEUTRAL',
    'GRAY': 'NEUTRAL',
  };

  /// Mengambil palet berdasarkan key dari database.
  ///
  /// Key yang tidak dikenal (termasuk key lama) dikembalikan ke palet teal.
  static ThemePalette fromKey(String? key) {
    final normalized = (key ?? '').trim().toUpperCase();
    if (normalized.isEmpty) return defaultPalette;

    final mapped = _legacyKeys[normalized] ?? normalized;

    for (final palette in available) {
      if (palette.key == mapped) {
        return palette;
      }
    }

    return defaultPalette;
  }
}
