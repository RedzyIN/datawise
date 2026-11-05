// MILIK ARSITEK. KONTRAK BEKU #3. Hasil dari Android (Anggota C).
import 'enums.dart';

class UsageReading {
  final UsageReadStatus status;
  final int totalBytes; // dalam byte
  final DateTime start, end; // periode yang dibaca
  final String? message;

  const UsageReading({
    required this.status,
    required this.totalBytes,
    required this.start,
    required this.end,
    required this.message,
  });
}
