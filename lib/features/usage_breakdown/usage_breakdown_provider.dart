import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/app_usage_sync_service.dart';
import '../../services/usage_breakdown_service.dart';
import '../../services/usage_service.dart';

class UsageBreakdownProvider extends ChangeNotifier {
  UsageBreakdownProvider(
    this._breakdownService,
    this._syncService,
    this._usageService,
  );

  final UsageBreakdownService _breakdownService;
  final AppUsageSyncService _syncService;
  final UsageService _usageService;

  UsageBreakdown? _breakdown;
  bool _isLoading = false;
  String? _errorMessage;

  UsageBreakdown? get breakdown => _breakdown;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Menyinkronkan statistik Android terbaru lalu membaca ulang `usage_records`.
  Future<void> load(DataPackage package, {bool sync = true}) async {
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
      if (sync && await _usageService.hasPermission()) {
        try {
          await _syncService.syncToday(package);
        } catch (_) {
          // Kegagalan sinkronisasi tidak menghapus rincian yang sudah tersimpan.
        }
      }

      _breakdown = await _breakdownService.build(packageId: packageId);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Gagal memuat rincian penggunaan aplikasi.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
