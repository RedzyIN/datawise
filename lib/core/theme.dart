// MILIK ARSITEK (tema dasar). Anggota D menyempurnakan di lib/shared/.
// Palet mengikuti dokumen Anggota D: biru muda, putih, bersih.
import 'package:flutter/material.dart';

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
    ),
    scaffoldBackgroundColor: latar,
    appBarTheme: const AppBarTheme(
      backgroundColor: latar,
      foregroundColor: teksUtama,
      elevation: 0,
    ),
  );
}
