import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/usage_service.dart';
import '../../services/usage_sync_service.dart';

class UsageProvider extends ChangeNotifier {
  UsageProvider(
    this._service,
    this._usageRepo,
    this._categoryRepo, {
    UsageSyncService? syncService,
  }) : _sync = syncService ?? UsageSyncServiceImpl(_service, _usageRepo);

  final UsageService _service;
  final UsageRepository _usageRepo;
  final QuotaCategoryRepository _categoryRepo;
  final UsageSyncService _sync;

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
      _hasPermission = false;
      _handleError(e);
    }

    notifyListeners();
  }

  Future<void> refresh(DataPackage package) async {
    _isLoading = true;
    _errorMessage = null;

    notifyListeners();

    try {
      // Hasil pembacaan Android langsung disimpan ke SQLite sebagai agregat
      // perangkat (DEVICE_TOTAL). Pembacaan ulang pada hari yang sama
      // memperbarui catatan yang sama, bukan menambah baris baru.
      final result = await _sync.syncToday(package);
      final reading = result.reading;

      _lastReading = reading;

      if (result.saved) {
        _lastRefresh = reading?.end;
        _errorMessage = null;
      } else {
        _errorMessage = result.message ?? 'Gagal membaca penggunaan internet.';
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
      final packageId = package.id;

      if (packageId == null) {
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

      final categories = await _categoryRepo.getByPackage(packageId);

      QuotaCategory? mainCategory;

      for (final category in categories) {
        if (category.categoryType == QuotaCategoryType.main) {
          mainCategory = category;
          break;
        }
      }

      if (mainCategory == null || mainCategory.id == null) {
        throw const AppException(
          AppException.notFound,
          'Kategori kuota utama tidak ditemukan.',
        );
      }

      final now = DateTime.now();
      final start = dateOnly(now);

      // periodEndAt harus lebih besar daripada periodStartAt.
      final end = now.isAfter(start)
          ? now
          : start.add(const Duration(seconds: 1));

      final record = UsageRecord(
        packageId: packageId,
        recordScope: UsageRecordScope.manualTotal,
        networkType: NetworkType.mobile,
        periodStartAt: start,
        periodEndAt: end,
        rxBytes: bytes,
        txBytes: 0,
        source: UsageSource.manual,
        sourceKey: 'manual_${packageId}_${dateToDb(start)}',
        recordedAt: now,
      );

      await _usageRepo.upsertRecordWithAllocations(record, (usageRecordId) {
        return [
          UsageAllocation(
            packageId: packageId,
            usageRecordId: usageRecordId,
            quotaCategoryId: mainCategory!.id,
            allocatedBytes: bytes,
            allocationMethod: AllocationMethod.manualUser,
            createdAt: now,
          ),
        ];
      });

      _errorMessage = null;
    } catch (e) {
      _handleError(e);
    }

    notifyListeners();
  }

  Future<void> deleteManualToday(DataPackage package) async {
    try {
      final packageId = package.id;

      if (packageId == null) {
        throw const AppException(
          AppException.validation,
          'Paket belum memiliki ID.',
        );
      }

      final now = DateTime.now();
      final start = dateOnly(now);
      final end = start.add(const Duration(days: 1));

      await _usageRepo.deleteManualRecords(packageId, start, end);

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

  /// Membuka pengaturan internet Android.
  ///
  /// Mengembalikan `false` bila halaman pengaturan tidak dapat dibuka, sehingga
  /// UI dapat menampilkan [errorMessage] lewat SnackBar.
  Future<bool> openInternetSettings() async {
    var opened = false;

    try {
      opened = await _service.openInternetSettings();
      _errorMessage = opened
          ? null
          : 'Pengaturan jaringan Android tidak dapat dibuka pada perangkat ini.';
    } catch (e) {
      _handleError(e);
    }

    notifyListeners();

    return opened;
  }
}
