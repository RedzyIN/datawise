import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/package_repository.dart';
import '../../repositories/usage_repository.dart';
import '../../services/usage_totals.dart';
import 'package_validator.dart';

class PackageProvider extends ChangeNotifier {
  PackageProvider(PackageRepository repository, {this.usageRepo})
    : _repository = repository;

  final PackageRepository _repository;

  /// Opsional agar daftar paket tetap dapat dipakai tanpa modul pemakaian.
  final UsageRepository? usageRepo;

  List<DataPackage> _packages = [];
  final Map<String, int> _usedBytesByPackage = {};

  bool _isLoading = false;
  String? _errorMessage;

  List<DataPackage> get packages => _packages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Pemakaian efektif (mobile) yang tercatat untuk satu paket.
  /// Angka ini memakai aturan yang sama dengan Dashboard sehingga
  /// DEVICE_TOTAL dan APP_USAGE tidak dijumlahkan bersamaan.
  int usedBytesFor(String? packageId) {
    if (packageId == null) return 0;
    return _usedBytesByPackage[packageId] ?? 0;
  }

  int remainingBytesFor(DataPackage package) {
    final remaining =
        package.advertisedTotalQuotaBytes - usedBytesFor(package.id);
    return remaining < 0 ? 0 : remaining;
  }

  /// Memuat pemakaian satu paket, misalnya saat halaman detail dibuka langsung.
  Future<void> loadUsageFor(DataPackage package) async {
    final packageId = package.id;
    final repo = usageRepo;
    if (packageId == null || repo == null) return;

    try {
      final used = totalEffectiveUsageBytes(await repo.getRecords(packageId));

      if (_usedBytesByPackage[packageId] == used) return;

      _usedBytesByPackage[packageId] = used;
      notifyListeners();
    } catch (_) {
      // Kegagalan memuat pemakaian tidak boleh menggagalkan informasi paket.
    }
  }

  Future<void> _loadUsageTotals(List<DataPackage> packages) async {
    final repo = usageRepo;
    if (repo == null) return;

    for (final package in packages) {
      final packageId = package.id;
      if (packageId == null) continue;

      try {
        _usedBytesByPackage[packageId] = totalEffectiveUsageBytes(
          await repo.getRecords(packageId),
        );
      } catch (_) {
        // Biarkan angka lama (atau 0) jika catatan pemakaian gagal dibaca.
      }
    }
  }

  Future<void> _reload(String userId) async {
    _packages = await _repository.getAll(userId);
    await _loadUsageTotals(_packages);
  }

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
      await _reload(userId);
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

      await _reload(package.userId);
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

      await _reload(package.userId);
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

      await _reload(userId);
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
      await _reload(userId);
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

      await _reload(userId);
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
