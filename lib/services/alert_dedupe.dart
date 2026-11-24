// Kunci deduplikasi dan id notifikasi bersama untuk seluruh jalur alert
// (Smart Alerts dan Data Limit Warning). Satu format kunci mencegah dua jalur
// evaluasi mengirim notifikasi yang sama pada hari yang sama.
import '../models/models.dart';

/// `<packageId>:<alertType>:<YYYY-MM-DD>` dalam tanggal lokal.
String alertDedupeKey({
  required String packageId,
  required AlertType type,
  required DateTime date,
}) {
  return '$packageId:${type.name}:${dateToDb(dateOnly(date))}';
}

/// Id notifikasi Android (32-bit, tidak negatif) yang stabil untuk kombinasi
/// paket, jenis alert, dan tanggal.
int alertNotificationId({
  required String packageId,
  required AlertType type,
  required DateTime date,
}) {
  final day = dateOnly(date);

  return Object.hash(packageId, type.name, day.year, day.month, day.day) &
      0x7fffffff;
}
