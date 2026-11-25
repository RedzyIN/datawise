// MILIK ARSITEK (tema dasar).
// Light Theme = standar develop (identitas teal).
// Dark Theme = adaptasi identitas yang sama, bukan palet baru.
import 'package:flutter/material.dart';

/// Satu sumber warna untuk Light dan Dark Theme.
/// Jangan menulis kode warna tema di tempat lain.
abstract final class AppPalette {
  // --- Identitas develop (light) ---
  static const Color teal = Color(0xFF00796F);
  static const Color deepTeal = Color(0xFF00695C);
  static const Color mint = Color(0xFFE4FBF7);
  static const Color ink = Color(0xFF073B3A);
  static const Color muted = Color(0xFF66817E);
  static const Color line = Color(0xFFD7F0EC);
  static const Color error = Color(0xFFC62828);

  // --- Adaptasi dark (turunan identitas teal yang sama) ---
  static const Color tealTerang = Color(0xFF31C9B8);
  static const Color hijauAksen = Color(0xFF5AE38C);
  static const Color inkGelap = Color(0xFF00201C);
  static const Color latarGelap = Color(0xFF0E1513);
  static const Color surfaceGelap = Color(0xFF16201E);
  static const Color surfaceTinggi = Color(0xFF1E2B28);
  static const Color teksGelap = Color(0xFFF2F7F6);
  static const Color teksMutedGelap = Color(0xFF9FB3AF);
  static const Color garisGelap = Color(0xFF2A3936);
  static const Color errorGelap = Color(0xFFFF8A80);
}

/// Warna peran halaman (Dashboard, Paket, Riwayat) yang selalu mengikuti
/// ThemeData aktif. Light memakai identitas develop apa adanya; dark memakai
/// adaptasi identitas teal yang sama.
final class AppPageColors {
  static AppPageColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const AppPageColors light = AppPageColors._(
    background: AppPalette.mint,
    backgroundEnd: Color(0xFFF7FFFD),
    surface: Colors.white,
    surfaceAlt: Color(0xFFDDF6F2),
    surfaceAccent: Color(0xFFD9FAF3),
    primary: AppPalette.teal,
    primaryDeep: AppPalette.deepTeal,
    onPrimary: Colors.white,
    ink: AppPalette.ink,
    muted: AppPalette.muted,
    line: AppPalette.line,
    mint: AppPalette.mint,
    barPale: Color(0xFFC8EDE7),
    barBright: Color(0xFF7FEBDD),
    noticeBg: Color(0xFFFFF5E8),
    noticeBorder: Color(0xFFF4D7AD),
    avatarBg: Color(0xFFB9C9C6),
    danger: AppPalette.error,
    dangerBg: Color(0xFFFFDAD6),
    success: Color(0xFF27865C),
    warning: Color(0xFFEF6C00),
    // Teks badge kuning: oranye yang lebih gelap agar kontras teks kecil pada
    // latar noticeBg tetap terbaca.
    warningInk: Color(0xFF8A4A00),
    isDark: false,
  );

  static const AppPageColors dark = AppPageColors._(
    background: AppPalette.latarGelap,
    backgroundEnd: Color(0xFF13201D),
    surface: AppPalette.surfaceGelap,
    surfaceAlt: AppPalette.surfaceTinggi,
    surfaceAccent: Color(0xFF1C2F2B),
    primary: AppPalette.tealTerang,
    primaryDeep: Color(0xFF2BB7A8),
    onPrimary: AppPalette.inkGelap,
    ink: AppPalette.teksGelap,
    muted: AppPalette.teksMutedGelap,
    line: AppPalette.garisGelap,
    mint: Color(0xFF1B2F2B),
    barPale: Color(0xFF28413D),
    barBright: Color(0xFF2FBFAD),
    noticeBg: Color(0xFF2A2318),
    noticeBorder: Color(0xFF4C3E24),
    avatarBg: Color(0xFF33403D),
    danger: AppPalette.errorGelap,
    dangerBg: Color(0xFF4A1F1C),
    success: AppPalette.hijauAksen,
    warning: Color(0xFFFFB74D),
    warningInk: Color(0xFFFFC179),
    isDark: true,
  );

  const AppPageColors._({
    required this.background,
    required this.backgroundEnd,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceAccent,
    required this.primary,
    required this.primaryDeep,
    required this.onPrimary,
    required this.ink,
    required this.muted,
    required this.line,
    required this.mint,
    required this.barPale,
    required this.barBright,
    required this.noticeBg,
    required this.noticeBorder,
    required this.avatarBg,
    required this.danger,
    required this.dangerBg,
    required this.success,
    required this.warning,
    required this.warningInk,
    required this.isDark,
  });

  final Color background;
  final Color backgroundEnd;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceAccent;
  final Color primary;
  final Color primaryDeep;
  final Color onPrimary;
  final Color ink;
  final Color muted;
  final Color line;
  final Color mint;
  final Color barPale;
  final Color barBright;
  final Color noticeBg;
  final Color noticeBorder;
  final Color avatarBg;
  final Color danger;
  final Color dangerBg;
  final Color success;
  final Color warning;

  /// Warna teks untuk status peringatan (badge kuning) dengan kontras memadai.
  final Color warningInk;
  final bool isDark;
}

// Tema Light Mode (acuan desain develop)
ThemeData buildAppTheme() {
  const teal = AppPalette.teal;
  const deepTeal = AppPalette.deepTeal;
  const mint = AppPalette.mint;
  const ink = AppPalette.ink;
  const muted = AppPalette.muted;
  const line = AppPalette.line;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: teal,
      primary: teal,
      secondary: deepTeal,
      surface: Colors.white,
      error: AppPalette.error,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: mint,
    dividerTheme: const DividerThemeData(color: line, thickness: 1),

    appBarTheme: const AppBarTheme(
      backgroundColor: mint,
      foregroundColor: ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: mint,
      height: 68,
      elevation: 2,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: deepTeal, size: 23);
        }

        return const IconThemeData(color: muted, size: 23);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: deepTeal,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          );
        }

        return const TextStyle(
          color: muted,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        );
      }),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: deepTeal,
        foregroundColor: Colors.white,
        overlayColor: mint,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: teal, overlayColor: mint),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: teal,
        side: const BorderSide(color: line),
        overlayColor: mint,
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: deepTeal,
      linearTrackColor: line,
    ),

    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: teal, width: 1.5),
      ),
    ),
  );
}

// Tema Dark Mode: background charcoal, surface bertingkat, teal terang sebagai
// identitas utama, hijau terang sebagai aksen (dipakai terbatas).
ThemeData buildDarkAppTheme() {
  const tealTerang = AppPalette.tealTerang;
  const hijauAksen = AppPalette.hijauAksen;
  const surface = AppPalette.surfaceGelap;
  const surfaceTinggi = AppPalette.surfaceTinggi;
  const teks = AppPalette.teksGelap;
  const muted = AppPalette.teksMutedGelap;
  const garis = AppPalette.garisGelap;

  final skema = ColorScheme.fromSeed(
    seedColor: AppPalette.teal,
    brightness: Brightness.dark,
    primary: tealTerang,
    onPrimary: AppPalette.inkGelap,
    secondary: hijauAksen,
    onSecondary: AppPalette.inkGelap,
    surface: surface,
    onSurface: teks,
    error: AppPalette.errorGelap,
    onError: AppPalette.inkGelap,
    outline: garis,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: skema,
    scaffoldBackgroundColor: AppPalette.latarGelap,
    canvasColor: AppPalette.latarGelap,
    dividerColor: garis,
    dividerTheme: const DividerThemeData(color: garis, thickness: 1),
    iconTheme: const IconThemeData(color: muted),
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: teks,
      displayColor: teks,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.latarGelap,
      foregroundColor: teks,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: tealTerang),
    ),

    cardTheme: const CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),

    dialogTheme: const DialogThemeData(
      backgroundColor: surfaceTinggi,
      surfaceTintColor: Colors.transparent,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: tealTerang.withValues(alpha: 0.16),
      shadowColor: hijauAksen.withValues(alpha: 0.18),
      height: 68,
      elevation: 8,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: tealTerang, size: 23);
        }

        return const IconThemeData(color: muted, size: 23);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: tealTerang,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          );
        }

        return const TextStyle(
          color: muted,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        );
      }),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tealTerang,
        foregroundColor: AppPalette.inkGelap,
        overlayColor: tealTerang.withValues(alpha: 0.2),
        disabledBackgroundColor: surfaceTinggi,
        disabledForegroundColor: muted,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tealTerang,
        overlayColor: tealTerang.withValues(alpha: 0.12),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tealTerang,
        side: const BorderSide(color: garis),
        overlayColor: tealTerang.withValues(alpha: 0.12),
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: hijauAksen,
      linearTrackColor: surfaceTinggi,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) return hijauAksen;
        return AppPalette.teksMutedGelap;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return tealTerang.withValues(alpha: 0.35);
        }
        return surfaceTinggi;
      }),
      trackOutlineColor: WidgetStateProperty.all(garis),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: const TextStyle(color: muted),
      labelStyle: const TextStyle(color: muted),
      helperStyle: const TextStyle(color: muted),
      prefixIconColor: muted,
      suffixIconColor: muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: garis),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: garis),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: tealTerang, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.errorGelap),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppPalette.errorGelap, width: 1.5),
      ),
    ),
  );
}
