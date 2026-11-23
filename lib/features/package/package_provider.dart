import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/package_repository.dart';
import 'package_validator.dart';

class PackageProvider extends ChangeNotifier {
  PackageProvider(PackageRepository repository) : _repository = repository;

  final PackageRepository _repository;

  List<DataPackage> _packages = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<DataPackage> get packages => _packages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Paket utama (ACTIVE) yang belum kedaluwarsa.
  DataPackage? get activePackage {
    for (final package in _packages) {
      if (package.status == PackageStatus.active && !package.isExpiredAt()) {
        return package;
      }
    }
    return null;
  }

  DataPackage? findById(String? id) {
    if (id == null) return null;
    for (final package in _packages) {
      if (package.id == id) return package;
    }
    return null;
  }

  // Memuat seluruh paket milik pengguna dan memperbarui status kedaluwarsa.
  Future<void> load(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (userId.trim().isEmpty) {
        throw const AppException(
          AppException.validation,
          'Identitas pengguna tidak ditemukan.',
        );
      }

      await _repository.markExpired(userId);
      _packages = await _repository.getAll(userId);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Gagal memuat daftar paket.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// [categories] disimpan bersamaan dengan paket dalam satu transaksi,
  /// sehingga kegagalan salah satu kategori tidak meninggalkan data parsial.
  Future<bool> addPackage(
    DataPackage package, {
    int initialUsedBytes = 0,
    List<QuotaCategory> categories = const [],
  }) async {
    return _run(() async {
      PackageValidator.validate(package);
      PackageValidator.validateInitialUsage(package, initialUsedBytes);

      await _repository.addWithCategories(
        package,
        categories: categories,
        initialUsedBytes: initialUsedBytes,
      );

      _packages = await _repository.getAll(package.userId);
    });
  }

  Future<bool> updatePackage(DataPackage package) async {
    return _run(() async {
      PackageValidator.validate(package);

      if (package.id == null || package.id!.trim().isEmpty) {
        throw const AppException(
          AppException.validation,
          'ID paket tidak ditemukan.',
        );
      }

      await _repository.update(package);

      _packages = await _repository.getAll(package.userId);
    });
  }

  // Mengarsipkan paket tanpa menghapus kategori atau riwayat penggunaan.
  Future<bool> archivePackage(String packageId, String userId) async {
    return _run(() async {
      final package = await _ownedPackage(packageId, userId);

      if (package.status == PackageStatus.archived) return;

      await _repository.update(
        package.copyWith(
          status: PackageStatus.archived,
          updatedAt: DateTime.now(),
        ),
      );

      _packages = await _repository.getAll(userId);
    });
  }

  /// Apakah paket sudah punya riwayat pemakaian (tidak boleh dihapus).
  /// Jika gagal dicek, dianggap punya riwayat demi keamanan data.
  Future<bool> hasUsageHistory(String packageId) async {
    try {
      return await _repository.hasUsageHistory(packageId);
    } catch (_) {
      return true;
    }
  }

  // Menghapus paket (hanya jika belum memiliki riwayat pemakaian).
  Future<bool> deletePackage(String packageId, String userId) async {
    return _run(() async {
      await _ownedPackage(packageId, userId);
      await _repository.delete(packageId);
      _packages = await _repository.getAll(userId);
    });
  }

  // Menjadikan paket sebagai satu-satunya paket ACTIVE.
  Future<bool> setActive(String userId, String packageId) async {
    return _run(() async {
      if (userId.trim().isEmpty || packageId.trim().isEmpty) {
        throw const AppException(
          AppException.validation,
          'Data paket tidak valid.',
        );
      }

      await _repository.setActive(userId, packageId);

      _packages = await _repository.getAll(userId);
    });
  }

  Future<DataPackage> _ownedPackage(String packageId, String userId) async {
    if (packageId.trim().isEmpty || userId.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Data paket tidak valid.',
      );
    }

    final package = await _repository.getById(packageId);

    if (package == null || package.userId != userId) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    return package;
  }

  Future<bool> _run(Future<void> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = 'Terjadi kesalahan. Silakan coba lagi.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;

    _errorMessage = null;
    notifyListeners();
  }
}
