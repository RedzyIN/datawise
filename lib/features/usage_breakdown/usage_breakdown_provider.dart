import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/app_icon_service.dart';
import '../../services/app_usage_sync_service.dart';
import '../../services/usage_breakdown_service.dart';
import '../../services/usage_service.dart';

class UsageBreakdownProvider extends ChangeNotifier {
  UsageBreakdownProvider(
    this._breakdownService,
    this._syncService,
    this._usageService, {
    AppIconService? iconService,
  }) : _iconService = iconService ?? PlatformAppIconService();

  final UsageBreakdownService _breakdownService;
  final AppUsageSyncService _syncService;
  final UsageService _usageService;
  final AppIconService _iconService;

  UsageBreakdown? _breakdown;
  bool _isLoading = false;
  String? _errorMessage;
  bool? _hasPermission;

  /// Cache ikon per package name. Ikon yang sama tidak diminta ulang setiap
  /// sheet dibuka atau daftar dimuat kembali.
  final Map<String, Uint8List> _icons = {};
  final Set<String> _requestedIcons = {};

  UsageBreakdown? get breakdown => _breakdown;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// null = belum diperiksa. `false` berarti Usage Access belum diberikan
  /// sehingga nama aplikasi tidak dapat dibaca dari Android.
  bool? get hasPermission => _hasPermission;

  /// Ikon launcher asli; null berarti UI memakai ikon fallback DATAWISE.
  Uint8List? iconFor(String packageName) => _icons[packageName];

  Future<void> openUsageAccessSettings() =>
      _usageService.openUsageAccessSettings();

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
      final granted = await _usageService.hasPermission();
      _hasPermission = granted;

      if (sync && granted) {
        try {
          await _syncService.syncToday(package);
        } catch (_) {
          // Kegagalan sinkronisasi tidak menghapus rincian yang sudah tersimpan.
        }
      }

      _breakdown = await _breakdownService.build(packageId: packageId);
      await _loadIcons(_breakdown!.apps);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Gagal memuat rincian penggunaan aplikasi.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Mengambil ikon untuk aplikasi yang belum punya ikon di cache.
  ///
  /// Entri `uid-xxxx` dilewati karena tidak memiliki package name sehingga
  /// tidak ada launcher icon yang bisa dibaca.
  Future<void> _loadIcons(List<AppUsageItem> apps) async {
    final missing = <String>[];

    for (final app in apps) {
      final packageName = app.appPackageName;
      if (packageName.isEmpty || packageName.startsWith('uid-')) continue;
      if (_requestedIcons.contains(packageName)) continue;
      missing.add(packageName);
    }

    if (missing.isEmpty) return;

    _requestedIcons.addAll(missing);

    try {
      final loaded = await _iconService.load(missing);
      if (loaded.isEmpty) return;

      _icons.addAll(loaded);
    } catch (_) {
      // Ikon hanya pelengkap tampilan; kegagalan tidak menggagalkan rincian.
    }
  }
}
