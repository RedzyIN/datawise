import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/usage_service.dart';

class UsageProvider extends ChangeNotifier {
  UsageProvider(this._service, this._usageRepo, this._packageRepo);

  final UsageService _service;
  final UsageRepository _usageRepo;
  final PackageRepository _packageRepo;

  bool _hasPermission = false;
  bool _isLoading = false;
  UsageReading? _lastReading;
  DateTime? _lastRefresh;
  String? _errorMessage;

  bool get hasPermission => _hasPermission;
  bool get isLoading => _isLoading;
  UsageReading? get lastReading => _lastReading;
  DateTime? get lastRefresh => _lastRefresh;
  String? get errorMessage => _errorMessage;

  void _handleError(Object error) {
    if (error is AppException) {
      _errorMessage = error.message;
    } else {
      _errorMessage = 'Terjadi kesalahan: $error';
    }
  }

  Future<void> checkPermission() async {
    try {
      _hasPermission = await _service.hasPermission();
      _errorMessage = _hasPermission
          ? null
          : 'Izin Usage Access belum diberikan.';
    } catch (e) {
      _handleError(e);
    }

    notifyListeners();
  }

  Future<void> refresh(DataPackage package) async {
    if (package.id == null) {
      _errorMessage = 'Paket belum memiliki ID.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final reading = await _service.refreshToday(package);

      _lastReading = reading;

      if (reading.status == UsageReadStatus.ok) {
        _lastRefresh = reading.end;
        _errorMessage = null;
      } else {
        _errorMessage = reading.message ?? 'Gagal membaca penggunaan internet.';
      }
    } catch (e) {
      _handleError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveManualToday(DataPackage package, int bytes) async {
    try {
      if (package.id == null) {
        throw const AppException(
          AppException.validation,
          'Paket belum memiliki ID.',
        );
      }

      if (bytes < 0) {
        throw const AppException(
          AppException.validation,
          'Penggunaan data tidak boleh negatif.',
        );
      }

      await _usageRepo.upsertRecord(
        package.id!,
        dateOnly(DateTime.now()),
        bytes,
        UsageSource.manual,
      );

      _errorMessage = null;
    } catch (e) {
      _handleError(e);
    }

    notifyListeners();
  }

  Future<void> deleteManualToday(DataPackage package) async {
    try {
      if (package.id == null) {
        throw const AppException(
          AppException.validation,
          'Paket belum memiliki ID.',
        );
      }

      await _usageRepo.deleteManual(package.id!, dateOnly(DateTime.now()));

      _errorMessage = null;
    } catch (e) {
      _handleError(e);
    }

    notifyListeners();
  }

  Future<void> setInitialUsed(DataPackage package, int bytes) async {
    try {
      if (package.id == null) {
        throw const AppException(
          AppException.validation,
          'Paket belum memiliki ID.',
        );
      }

      if (bytes < 0) {
        throw const AppException(
          AppException.validation,
          'Penggunaan awal tidak boleh negatif.',
        );
      }

      final existingPackage = await _packageRepo.getById(package.id!);

      if (existingPackage == null) {
        throw const AppException(
          AppException.notFound,
          'Paket tidak ditemukan.',
        );
      }

      final updatedPackage = existingPackage.copyWith(
        initialUsedBytes: bytes,
        updatedAt: DateTime.now(),
      );

      await _packageRepo.update(updatedPackage);
      _errorMessage = null;
    } catch (e) {
      _handleError(e);
    }

    notifyListeners();
  }

  Future<void> openUsageAccessSettings() async {
    try {
      await _service.openUsageAccessSettings();
      _errorMessage = null;
    } catch (e) {
      _handleError(e);
    }

    notifyListeners();
  }

  Future<void> openInternetSettings() async {
    try {
      await _service.openInternetSettings();
      _errorMessage = null;
    } catch (e) {
      _handleError(e);
    }

    notifyListeners();
  }
}
