import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/data_limit_service.dart';

class DataLimitProvider extends ChangeNotifier {
  DataLimitProvider(this._service);

  final DataLimitService _service;

  DataLimitSetting? _setting;
  DataLimitEvaluation? _evaluation;
  int _usedBytes = 0;
  bool _notificationsEnabled = true;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  DataLimitSetting? get setting => _setting;
  DataLimitEvaluation? get evaluation => _evaluation;
  int get usedBytes => _usedBytes;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  Future<void> load(DataPackage package, String userId) async {
    final packageId = package.id;

    if (packageId == null) {
      _errorMessage = 'Paket belum memiliki ID.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _refresh(packageId, userId);
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

      await _refresh(packageId, userId);
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

  Future<void> _refresh(String packageId, String userId) async {
    _setting = await _service.getDailyLimit(packageId);
    _usedBytes = await _service.usedBytesOn(packageId, DateTime.now());
    _notificationsEnabled = await _service.notificationsEnabledFor(userId);
    _evaluation = await _service.evaluateAndNotify(
      packageId: packageId,
      userId: userId,
      usedBytes: _usedBytes,
    );
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}
