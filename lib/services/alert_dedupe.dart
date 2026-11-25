// Kunci deduplikasi dan id notifikasi bersama untuk seluruh jalur alert
// (Smart Alerts dan Data Limit Warning). Satu format kunci mencegah dua jalur
// evaluasi mengirim notifikasi yang sama pada hari yang sama.
import 'dart:convert';

import '../models/models.dart';

/// `<packageId>:<alertType>:<YYYY-MM-DD>` dalam tanggal lokal.
String alertDedupeKey({
  required String packageId,
  required AlertType type,
  required DateTime date,
}) {
  return '$packageId:${type.name}:${dateToDb(dateOnly(date))}';
}

/// Id notifikasi Android (32-bit, tidak negatif) yang stabil untuk sebuah kunci
/// deduplikasi.
///
/// Nilai sengaja dihitung sendiri (FNV-1a 32-bit) dan bukan memakai
/// `Object.hash`/`hashCode`, supaya id yang sama dijamin dihasilkan lagi pada
/// proses aplikasi berikutnya maupun dari isolate background. Plugin
/// notifikasi mengganti notifikasi lama yang memakai id sama, jadi id yang
/// stabil mencegah tumpukan notifikasi untuk kejadian yang sama.
int stableNotificationId(String key) {
  var hash = 0x811c9dc5;

  for (final byte in utf8.encode(key)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }

  final id = hash & 0x7fffffff;

  // 0 dipakai Android sebagai "tidak ada id"; jangan pernah dipakai.
  return id == 0 ? 1 : id;
}

/// Id notifikasi untuk kombinasi paket, jenis alert, dan tanggal.
int alertNotificationId({
  required String packageId,
  required AlertType type,
  required DateTime date,
}) {
  return stableNotificationId(
    alertDedupeKey(packageId: packageId, type: type, date: date),
  );
}
