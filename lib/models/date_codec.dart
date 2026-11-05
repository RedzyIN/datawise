// MILIK ARSITEK. Pembantu konversi tanggal/waktu sesuai kontrak beku:
// tanggal = 'YYYY-MM-DD' (lokal), waktu = ms UTC.

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateToDb(DateTime d) {
  final x = dateOnly(d);
  return '${x.year.toString().padLeft(4, '0')}-'
      '${x.month.toString().padLeft(2, '0')}-'
      '${x.day.toString().padLeft(2, '0')}';
}

DateTime dateFromDb(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

int timeToMs(DateTime d) => d.toUtc().millisecondsSinceEpoch;

DateTime timeFromMs(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
