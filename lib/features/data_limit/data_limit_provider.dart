import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/dashboard_data_limit_calculator.dart';
import '../../services/data_limit_background_service.dart';
import '../../services/data_limit_service.dart';

class DataLimitProvider extends ChangeNotifier {
  DataLimitProvider(this._service);

  final DataLimitService _service;

  DataLimitSetting? _setting;
  DataLimitEvaluation? _evaluation;
  PlannerResult? _planner;
  DataPackage? _package;
  int _usedBytes = 0;
  bool _notificationsEnabled = true;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  DataLimitSetting? get setting => _setting;
  DataLimitEvaluation? get evaluation => _evaluation;

  /// Hasil PlannerService untuk paket yang sedang dibuka. Dipakai UI untuk
  /// menjelaskan fallback, bukan angka hardcode.
  PlannerResult? get planner => _planner;

  int get usedBytes => _usedBytes;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  /// Sumber batas yang benar-benar dipakai: manual, fallback Data Planner,
  /// atau belum ada.
  DataLimitSource get limitSource =>
      _evaluation?.limitSource ?? DataLimitSource.none;

  bool get usesPlannerTarget => limitSource == DataLimitSource.planner;
  bool get usesManualLimit => limitSource == DataLimitSource.manual;

  double? get plannerDailyTargetBytes => _planner?.dailyTargetBytes;

  /// Persentase pemakaian terhadap batas yang berlaku (null bila belum ada).
  double? get usagePercent => _evaluation?.usagePercent;

  Future<void> load(DataPackage package, String userId) async {
    final packageId = package.id;

    if (packageId == null) {
      _errorMessage = 'Paket belum memiliki ID.';
      notifyListeners();
      return;
    }

    // Paket aktif bisa berganti; state paket sebelumnya tidak boleh dipakai
    // untuk paket baru (mis. batas atau status milik paket lama).
    final isNewPackage = packageId != _package?.id;
    _package = package;

    if (isNewPackage) {
      _setting = null;
      _evaluation = null;
      _planner = null;
      _usedBytes = 0;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _refresh(userId);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Gagal memuat batas penggunaan data.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> save({
    required String packageId,
    required String userId,
    required bool isEnabled,
    required int? dailyLimitBytes,
    required int warnAtPercent,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final existing = await _service.getDailyLimit(packageId);

      await _service.saveDailyLimit(
        DataLimitSetting(
          packageId: packageId,
          dailyLimitBytes: dailyLimitBytes,
          warnAtPercent: warnAtPercent,
          limitAtPercent: existing?.limitAtPercent ?? 100,
          isEnabled: isEnabled,
          updatedAt: DateTime.now(),
        ),
      );

      await _refresh(userId);

      // Pastikan pemeriksaan latar belakang tetap terjadwal setelah pengaturan
      // diubah; pekerjaan yang sudah ada dipertahankan.
      await DataLimitBackgroundScheduler.schedule();

      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = 'Gagal menyimpan batas harian.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> _refresh(String userId) async {
    final package = _package;

    if (package == null || package.id == null) {
      throw const AppException(
        AppException.validation,
        'Paket belum memiliki ID.',
      );
    }

    final packageId = package.id!;

    _setting = await _service.getDailyLimit(packageId);
    _usedBytes = await _service.usedBytesOn(packageId, DateTime.now());

    // Target planner dihitung dari paket yang sama agar batas paket lama tidak
    // pernah dipakai untuk paket aktif yang baru.
    try {
      _planner = await _service.plannerResultFor(package);
    } catch (_) {
      _planner = null;
    }

    _notificationsEnabled = await _service.notificationsEnabledFor(userId);
    _evaluation = await _service.evaluateAndNotify(
      packageId: packageId,
      userId: userId,
      usedBytes: _usedBytes,
      plannerResult: _planner,
    );
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}
