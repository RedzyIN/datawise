import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/quota_category_repository.dart';

/// Pengelola kategori kuota satu paket (Multiple Quota Management).
///
/// Aturan kapasitas: total seluruh kategori tidak boleh melebihi total kuota
/// paket. Kategori tambahan mengambil jatah dari kategori MAIN sehingga total
/// paket tidak pernah bertambah dua kali.
class QuotaCategoryProvider extends ChangeNotifier {
  QuotaCategoryProvider(this._repository);

  final QuotaCategoryRepository _repository;

  String? _packageId;
  List<QuotaCategory> _categories = const [];
  bool _isLoading = false;
  String? _errorMessage;

  List<QuotaCategory> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  QuotaCategory? get mainCategory {
    for (final category in _categories) {
      if (category.categoryType == QuotaCategoryType.main) return category;
    }
    return null;
  }

  List<QuotaCategory> get additionalCategories => _categories
      .where((category) => category.categoryType != QuotaCategoryType.main)
      .toList();

  /// Total kapasitas yang sudah dibagi ke seluruh kategori paket.
  int get totalAllocatedBytes =>
      _categories.fold(0, (total, category) => total + category.capacityBytes);

  int get mainCapacityBytes => mainCategory?.capacityBytes ?? 0;

  Future<void> load(String packageId) async {
    _packageId = packageId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _categories = await _repository.getByPackage(packageId);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Gagal memuat kategori kuota.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> add(QuotaCategory category) {
    return _run(() async {
      if (category.packageId.trim().isEmpty) {
        throw const AppException(
          AppException.validation,
          'Paket kategori tidak ditemukan.',
        );
      }
      if (category.categoryType == QuotaCategoryType.main) {
        throw const AppException(
          AppException.validation,
          'Kategori utama dibuat otomatis bersama paket.',
        );
      }
      _validateContent(category);
      if (mainCategory == null) {
        throw const AppException(
          AppException.notFound,
          'Kategori utama paket tidak ditemukan.',
        );
      }
      if (category.capacityBytes >= mainCapacityBytes) {
        throw const AppException(
          AppException.validation,
          'Kapasitas kategori harus lebih kecil dari sisa kuota utama.',
        );
      }

      await _repository.add(category);
    });
  }

  Future<bool> update(QuotaCategory category) {
    return _run(() async {
      if (category.id == null) {
        throw const AppException(
          AppException.validation,
          'ID kategori tidak ditemukan.',
        );
      }
      _validateContent(category);

      await _repository.update(category);
    });
  }

  void _validateContent(QuotaCategory category) {
    if (category.categoryName.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Nama kategori wajib diisi.',
      );
    }
    if (category.capacityBytes <= 0) {
      throw const AppException(
        AppException.validation,
        'Kapasitas kategori harus lebih dari 0.',
      );
    }
  }

  Future<bool> delete(String categoryId) {
    return _run(() => _repository.delete(categoryId));
  }

  Future<bool> setEnabled(QuotaCategory category, bool enabled) {
    return _run(
      () => _repository.update(category.copyWith(isEnabled: enabled)),
    );
  }

  Future<bool> _run(Future<void> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
      if (_packageId != null) {
        _categories = await _repository.getByPackage(_packageId!);
      }
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
