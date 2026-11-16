import '../../models/models.dart';

class PackageValidator {
  static void validate(DataPackage package) {
    if (package.userId.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Identitas pengguna tidak ditemukan.',
      );
    }

    if (package.packageName.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Nama paket wajib diisi.',
      );
    }

    if (package.advertisedTotalQuotaBytes <= 0) {
      throw const AppException(
        AppException.validation,
        'Total kuota harus lebih dari 0.',
      );
    }

    if (package.endDate.isBefore(package.startDate)) {
      throw const AppException(
        AppException.validation,
        'Tanggal berakhir tidak boleh sebelum tanggal mulai.',
      );
    }
  }

  static void validateInitialUsage(DataPackage package, int usedBytes) {
    if (usedBytes < 0) {
      throw const AppException(
        AppException.validation,
        'Kuota terpakai tidak boleh negatif.',
      );
    }

    if (usedBytes > package.advertisedTotalQuotaBytes) {
      throw const AppException(
        AppException.validation,
        'Kuota terpakai tidak boleh melebihi total kuota.',
      );
    }
  }
}
