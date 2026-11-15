import '../../models/models.dart';

class PackageValidator {
  static void validate(DataPackage package) {
    if (package.userId.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Identitas pengguna tidak ditemukan.',
      );
    }

    if (package.name.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Nama paket wajib diisi.',
      );
    }

    if (package.operator.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Nama operator wajib diisi.',
      );
    }

    if (package.totalBytes <= 0) {
      throw const AppException(
        AppException.validation,
        'Total kuota harus lebih dari 0.',
      );
    }

    if (package.initialUsedBytes < 0 ||
        package.initialUsedBytes > package.totalBytes) {
      throw const AppException(
        AppException.validation,
        'Pemakaian awal tidak valid.',
      );
    }

    if (!package.endDate.isAfter(package.startDate)) {
      throw const AppException(
        AppException.validation,
        'Tanggal berakhir harus setelah tanggal mulai.',
      );
    }

    if (package.price != null && package.price! < 0) {
      throw const AppException(
        AppException.validation,
        'Harga tidak boleh negatif.',
      );
    }
  }
}
