// MILIK ARSITEK. Helper tampilan - anggota lain tinggal memakai.
// Pembulatan HANYA di tampilan, tidak di perhitungan.
import 'constants.dart';

const List<String> _bulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

String _komaDesimal(double v, int digit) =>
    v.toStringAsFixed(digit).replaceAll('.', ',');

/// 1500000000 -> '1,50 GB'
String formatBytes(num bytes) {
  if (bytes >= kBytesPerGB) {
    return '${_komaDesimal(bytes / kBytesPerGB, 2)} GB';
  }
  if (bytes >= kBytesPerMB) {
    return '${_komaDesimal(bytes / kBytesPerMB, 1)} MB';
  }
  return '${bytes.round()} B';
}

/// DateTime(2026, 11, 5) -> '05 Nov 2026'
String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_bulan[d.month - 1]} ${d.year}';

/// 150000 -> 'Rp 150.000'
String formatRupiah(int amount) {
  final s = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}Rp $buf';
}
