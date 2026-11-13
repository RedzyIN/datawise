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

  DataPackage? get activePackage {
    for (final package in _packages) {
      if (package.isActive) return package;
    }
    return null;
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Memuat seluruh paket milik pengguna.
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

  // Menambahkan paket baru.
  Future<bool> addPackage(DataPackage p) async {
    return _run(() async {
      PackageValidator.validate(p);

      await _repository.add(p);

      _packages = await _repository.getAll(p.userId);
    });
  }

  // Memperbarui informasi paket.
  Future<bool> updatePackage(DataPackage p) async {
    return _run(() async {
      PackageValidator.validate(p);

      if (p.id == null) {
        throw const AppException(
          AppException.validation,
          'ID paket tidak ditemukan.',
        );
      }

      await _repository.update(p);

      _packages = await _repository.getAll(p.userId);
    });
  }

  // Menghapus paket.
  Future<bool> deletePackage(int id, String userId) async {
    return _run(() async {
      if (id <= 0 || userId.trim().isEmpty) {
        throw const AppException(
          AppException.validation,
          'Data paket tidak valid.',
        );
      }

      final package = await _repository.getById(id);

      if (package == null || package.userId != userId) {
        throw const AppException(
          AppException.notFound,
          'Paket tidak ditemukan.',
        );
      }

      await _repository.delete(id);

      _packages = await _repository.getAll(userId);
    });
  }

  // Menjadikan paket sebagai paket aktif.
  Future<void> setActive(String userId, int packageId) async {
    await _run(() async {
      if (userId.trim().isEmpty || packageId <= 0) {
        throw const AppException(
          AppException.validation,
          'Data paket tidak valid.',
        );
      }

      await _repository.setActive(userId, packageId);

      _packages = await _repository.getAll(userId);
    });
  }

  // Menjalankan operasi dengan penanganan loading dan error.
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
