import '../../models/models.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

const _longMonths = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

/// Memisahkan nilai dan satuan, mis. ('30,00', 'GB').
(String, String) splitBytes(num bytes) {
  if (bytes >= 1000000000) {
    return ((bytes / 1000000000).toStringAsFixed(2).replaceAll('.', ','), 'GB');
  }
  return ((bytes / 1000000).toStringAsFixed(2).replaceAll('.', ','), 'MB');
}

String formatBytes(num bytes) {
  final (value, unit) = splitBytes(bytes);
  return '$value $unit';
}

// 1 GB = 1.000.000.000 byte (Kontrak Data v1.0). Konversi hanya terjadi di UI.
const int _bytesPerGb = 1000000000;
const int _bytesPerMb = 1000000;

/// Mengubah angka input satuan GB atau MB menjadi byte.
///
/// Nilai negatif dibulatkan menjadi 0 agar tidak pernah tersimpan sebagai
/// pemakaian negatif.
int quotaBytesFromInput(num value, {required bool inGigabytes}) {
  final factor = inGigabytes ? _bytesPerGb : _bytesPerMb;
  final bytes = (value * factor).round();
  return bytes < 0 ? 0 : bytes;
}

/// Sisa kuota awal paket: total kuota dikurangi pemakaian awal.
int remainingInitialBytes(int totalBytes, int initialUsedBytes) {
  final remaining = totalBytes - initialUsedBytes;
  return remaining < 0 ? 0 : remaining;
}

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatDateLong(DateTime d) =>
    '${d.day} ${_longMonths[d.month - 1]} ${d.year}';

/// Sisa masa berlaku sebagai pecahan 0..1 (berdasarkan tanggal).
double timeLeftFraction(DataPackage p) {
  final total = p.endDate.difference(p.startDate).inDays;
  if (total <= 0) return 0;
  return (p.daysRemaining() / total).clamp(0.0, 1.0).toDouble();
}
