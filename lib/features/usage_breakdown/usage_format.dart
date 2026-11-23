// Format satuan khusus rincian per aplikasi agar nilai kecil tidak tampil
// sebagai ribuan byte. Tampilan MB/GB sama dengan Dashboard (koma desimal).
import '../../core/constants.dart';

const int _bytesPerKB = 1000;

/// 512 -> '512 B', 1500 -> '1,5 KB', 1530000000 -> '1,53 GB'
String formatUsageBytes(num bytes) {
  final value = bytes < 0 ? 0 : bytes;

  if (value >= kBytesPerGB) {
    return '${_decimal(value / kBytesPerGB, 2)} GB';
  }
  if (value >= kBytesPerMB) {
    return '${_decimal(value / kBytesPerMB, 1)} MB';
  }
  if (value >= _bytesPerKB) {
    return '${_decimal(value / _bytesPerKB, 1)} KB';
  }
  return '${value.round()} B';
}

String _decimal(num value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');
