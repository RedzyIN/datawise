
// MILIK ARSITEK (tema dasar).
// Penambahan Dark Mode untuk fitur Settings Anggota A.
import 'package:flutter/material.dart';

// Tema Light Mode
ThemeData buildAppTheme() {
  const biruUtama = Color(0xFF3B9AE8);
  const biruTombol = Color(0xFF1F6FB8);
  const latar = Color(0xFFF5F9FD);
  const teksUtama = Color(0xFF12263A);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: biruUtama,
      primary: biruTombol,
      surface: Colors.white,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: latar,
    appBarTheme: const AppBarTheme(
      backgroundColor: latar,
      foregroundColor: teksUtama,
      elevation: 0,
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
