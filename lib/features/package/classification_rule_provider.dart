import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/classification_rule_repository.dart';

/// Pengelola aturan klasifikasi penggunaan aplikasi untuk satu paket.
///
/// Validasi isi aturan tetap berada di repository; provider hanya memanggil
/// kontrak yang sudah tersedia dan meneruskan pesan kesalahannya ke UI.
class ClassificationRuleProvider extends ChangeNotifier {
  ClassificationRuleProvider(this._repository);

  final ClassificationRuleRepository _repository;

  String? _packageId;
  List<ClassificationRule> _rules = const [];
  bool _isLoading = false;
  String? _errorMessage;

  List<ClassificationRule> get rules => _rules;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load(String packageId) async {
    final isSamePackage = _packageId == packageId;
    _packageId = packageId;
    _isLoading = true;
    _errorMessage = null;
    // Aturan paket sebelumnya tidak boleh tampil saat paket baru dimuat.
    if (!isSamePackage) _rules = const [];
    notifyListeners();

    try {
      _rules = await _repository.getByPackage(packageId);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Gagal memuat aturan klasifikasi.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> add(ClassificationRule rule) {
    return _run(() async {
      await _repository.add(rule);
    });
  }

  Future<bool> update(ClassificationRule rule) {
    return _run(() => _repository.update(rule));
  }

  Future<bool> delete(String ruleId) {
    return _run(() => _repository.delete(ruleId));
  }

  Future<bool> setEnabled(ClassificationRule rule, bool enabled) {
    return _run(
      () => _repository.update(
        ClassificationRule(
          id: rule.id,
          quotaCategoryId: rule.quotaCategoryId,
          ruleName: rule.ruleName,
          appPackageName: rule.appPackageName,
          startMinute: rule.startMinute,
          endMinute: rule.endMinute,
          daysOfWeekMask: rule.daysOfWeekMask,
          priority: rule.priority,
          isEnabled: enabled,
          createdAt: rule.createdAt,
        ),
      ),
    );
  }

  Future<bool> _run(Future<void> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
      final packageId = _packageId;
      if (packageId != null) {
        _rules = await _repository.getByPackage(packageId);
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
