// PEMILIK: Anggota B. KONTRAK BEKU #1 & #4.
// Fungsi MURNI: tanpa database, tanpa jam sistem. Rumus: lihat dokumen B bagian 4
// dan kerangka acuan di bagian 11.1.
// TODO(B): implementasikan; 10 kasus uji di test/package/planner_service_test.dart
import '../models/models.dart';

class PlannerService {
  static PlannerResult calculate({
    required DataPackage package,
    required int totalUsedBytes,
    required int todayUsedBytes,
    required DateTime today,
  }) {
    throw UnimplementedError('TODO(B): PlannerService.calculate');
  }
}

class PackageValidator {
  /// null = valid, selain itu pesan error (urutan & teks: dokumen B bagian 11.2).
  static String? validate(DataPackage p) {
    throw UnimplementedError('TODO(B): PackageValidator.validate');
  }
}
