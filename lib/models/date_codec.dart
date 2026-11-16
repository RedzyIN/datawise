// Tanggal kalender disimpan sebagai YYYY-MM-DD.
// Timestamp disimpan sebagai ISO-8601 UTC. Fungsi millisecond tetap tersedia
// untuk kebutuhan migrasi dari skema database lama.

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String dateToDb(DateTime value) {
  final date = dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime dateFromDb(String value) {
  final parts = value.split('-');
  if (parts.length != 3) {
    throw FormatException('Format tanggal tidak valid: $value');
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String timeToIso(DateTime value) => value.toUtc().toIso8601String();

DateTime timeFromIso(String value) => DateTime.parse(value).toLocal();

int timeToMs(DateTime value) => value.toUtc().millisecondsSinceEpoch;

DateTime timeFromMs(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
