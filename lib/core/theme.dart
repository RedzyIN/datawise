// MILIK ARSITEK (tema dasar).
// Penambahan Dark Mode untuk fitur Settings Anggota A.
import 'package:flutter/material.dart';

// Tema Light Mode
ThemeData buildAppTheme() {
  const teal = Color(0xFF00796F);
  const deepTeal = Color(0xFF00695C);
  const mint = Color(0xFFE4FBF7);
  const ink = Color(0xFF073B3A);
  const muted = Color(0xFF66817E);
  const line = Color(0xFFD7F0EC);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: teal,
      primary: teal,
      secondary: deepTeal,
      surface: Colors.white,
      error: const Color(0xFFC62828),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: mint,

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

// Tema Dark Mode
ThemeData buildDarkAppTheme() {
  const biruUtama = Color(0xFF3B9AE8);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: biruUtama,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}
