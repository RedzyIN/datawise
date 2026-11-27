import 'package:flutter/material.dart';

import '../models/theme_palette.dart';

// MILIK ARSITEK (tema dasar).
// Light Theme = standar develop (identitas teal).
// Dark Theme = adaptasi identitas yang sama, bukan palet baru.

abstract final class AppPalette {
  static const Color teal = Color(0xFF00796F);
  static const Color deepTeal = Color(0xFF00695C);
  static const Color mint = Color(0xFFE4FBF7);
  static const Color ink = Color(0xFF073B3A);
  static const Color muted = Color(0xFF66817E);
  static const Color line = Color(0xFFD7F0EC);
  static const Color error = Color(0xFFC62828);

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

final class AppPageColors extends ThemeExtension<AppPageColors> {
  static AppPageColors of(BuildContext context) {
    final theme = Theme.of(context);

    return theme.extension<AppPageColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

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

  factory AppPageColors.fromPalette(
    ThemePaletteColors colors, {
    required bool isDark,
  }) {
    final muted = Color.lerp(colors.text, colors.background, 0.45)!;
    final line = Color.lerp(colors.text, colors.background, 0.82)!;

    return AppPageColors._(
      background: colors.background,
      backgroundEnd: Color.lerp(colors.background, colors.surface, 0.5)!,
      surface: colors.surface,
      surfaceAlt: Color.lerp(colors.surface, colors.primary, 0.10)!,
      surfaceAccent: Color.lerp(colors.surface, colors.accent, 0.18)!,
      primary: colors.primary,
      primaryDeep: colors.secondary,
      onPrimary: isDark ? colors.background : Colors.white,
      ink: colors.text,
      muted: muted,
      line: line,
      mint: colors.background,
      barPale: Color.lerp(colors.background, colors.accent, 0.35)!,
      barBright: colors.accent,
      noticeBg: Color.lerp(colors.surface, colors.accent, 0.12)!,
      noticeBorder: Color.lerp(colors.surface, colors.accent, 0.35)!,
      avatarBg: muted,
      danger: isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
      dangerBg: isDark ? const Color(0xFF4A1F1C) : const Color(0xFFFFDAD6),
      success: isDark ? const Color(0xFF5AE38C) : const Color(0xFF27865C),
      warning: isDark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00),
      warningInk: isDark ? const Color(0xFFFFC179) : const Color(0xFF8A4A00),
      isDark: isDark,
    );
  }

  @override
  AppPageColors copyWith() => this;

  @override
  AppPageColors lerp(covariant AppPageColors? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

// Tema Light Mode bawaan.
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
    extensions: const <ThemeExtension<dynamic>>[AppPageColors.light],
  );
}

// Tema Dark Mode bawaan.
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
    extensions: const <ThemeExtension<dynamic>>[AppPageColors.dark],
  );
}

/// Membuat ThemeData berdasarkan palet pilihan pengguna.
ThemeData buildPaletteAppTheme(ThemePalette palette, {required bool isDark}) {
  final colors = isDark ? palette.dark : palette.light;
  final brightness = isDark ? Brightness.dark : Brightness.light;

  final baseTheme = isDark ? buildDarkAppTheme() : buildAppTheme();

  final colorScheme = ColorScheme.fromSeed(
    seedColor: colors.primary,
    brightness: brightness,
    primary: colors.primary,
    onPrimary: isDark ? colors.background : Colors.white,
    secondary: colors.secondary,
    onSecondary: isDark ? colors.background : Colors.white,
    surface: colors.surface,
    onSurface: colors.text,
    error: isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
    outline: Color.lerp(colors.text, colors.background, 0.72)!,
  );

  final pageColors = AppPageColors.fromPalette(colors, isDark: isDark);

  final disabledBackground = Color.lerp(
    colors.surface,
    colors.background,
    0.5,
  )!;

  final borderRadius = BorderRadius.circular(14);

  final normalBorder = OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: BorderSide(color: pageColors.line),
  );

  final focusedBorder = OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: BorderSide(color: colors.primary, width: 1.5),
  );

  final errorBorder = OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: BorderSide(color: pageColors.danger),
  );

  return baseTheme.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    dividerColor: pageColors.line,
    dividerTheme: DividerThemeData(color: pageColors.line, thickness: 1),

    // AppBar mengikuti palet aktif.
    appBarTheme: baseTheme.appBarTheme.copyWith(
      backgroundColor: colors.background,
      foregroundColor: colors.text,
      iconTheme: IconThemeData(color: colors.primary),
      actionsIconTheme: IconThemeData(color: colors.primary),
    ),

    // Navigasi bawah: Beranda, Paket, Riwayat, Pengaturan.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.primary.withValues(alpha: 0.16),
      shadowColor: colors.primary.withValues(alpha: isDark ? 0.18 : 0.08),
      height: 68,
      elevation: isDark ? 8 : 2,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: colors.primary, size: 23);
        }

        return IconThemeData(color: pageColors.muted, size: 23);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            color: colors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          );
        }

        return TextStyle(
          color: pageColors.muted,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        );
      }),
    ),

    iconTheme: IconThemeData(color: colors.text),

    textTheme: baseTheme.textTheme.apply(
      bodyColor: colors.text,
      displayColor: colors.text,
    ),

    // Kartu dan dialog.
    cardTheme: baseTheme.cardTheme.copyWith(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),

    dialogTheme: baseTheme.dialogTheme.copyWith(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),

    // Tombol utama.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: isDark ? colors.background : Colors.white,
        disabledBackgroundColor: disabledBackground,
        disabledForegroundColor: pageColors.muted,
        overlayColor: colors.accent.withValues(alpha: 0.18),
      ),
    ),

    // Tombol Elevated.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: isDark ? colors.background : Colors.white,
        disabledBackgroundColor: disabledBackground,
        disabledForegroundColor: pageColors.muted,
        overlayColor: colors.accent.withValues(alpha: 0.18),
        elevation: 0,
      ),
    ),

    // Tombol teks.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        overlayColor: colors.accent.withValues(alpha: 0.18),
      ),
    ),

    // Tombol outline.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        side: BorderSide(color: colors.primary),
        overlayColor: colors.accent.withValues(alpha: 0.18),
      ),
    ),

    // Tombol ikon.
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.primary,
        disabledForegroundColor: pageColors.muted,
      ),
    ),

    // Kolom input.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      hintStyle: TextStyle(color: pageColors.muted),
      labelStyle: TextStyle(color: pageColors.muted),
      helperStyle: TextStyle(color: pageColors.muted),
      prefixIconColor: pageColors.muted,
      suffixIconColor: pageColors.muted,
      border: normalBorder,
      enabledBorder: normalBorder,
      focusedBorder: focusedBorder,
      errorBorder: errorBorder,
      focusedErrorBorder: errorBorder,
    ),

    // Switch.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary;
        }

        return pageColors.muted;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary.withValues(alpha: 0.35);
        }

        return disabledBackground;
      }),
      trackOutlineColor: WidgetStateProperty.all(pageColors.line),
    ),

    // Checkbox.
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary;
        }

        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(
        isDark ? colors.background : Colors.white,
      ),
      side: BorderSide(color: pageColors.muted),
    ),

    // Radio.
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primary;
        }

        return pageColors.muted;
      }),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: pageColors.surfaceAlt,
    ),

    extensions: <ThemeExtension<dynamic>>[pageColors],
  );
}
