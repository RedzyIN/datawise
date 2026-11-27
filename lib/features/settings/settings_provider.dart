import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/settings_repository.dart';
import '../../services/data_export_service.dart';
import '../../services/usage_service.dart';

/// Status satu proses ekspor data.
enum DataExportStatus { idle, running, success, failure }

/// State halaman Pengaturan: preferensi notifikasi, status izin akses
/// penggunaan, dan proses ekspor data.
///
/// UI hanya membaca state ini; seluruh akses Repository dan Service terjadi di
/// lapisan provider/service.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(
    this._settingsRepository,
    this._usageService,
    this._exportService,
  );

  final SettingsRepository _settingsRepository;
  final UsageService _usageService;
  final DataExportService _exportService;

  String? _userId;
  bool _notificationsEnabled = true;
  bool _usagePermissionGranted = false;
  bool _isCheckingPermission = false;
  DataExportStatus _exportStatus = DataExportStatus.idle;
  String? _exportMessage;
  String? _errorMessage;
  int _requestId = 0;
  bool _disposed = false;

  String? get userId => _userId;

  bool get isSignedIn => _userId != null;

  bool get notificationsEnabled => _notificationsEnabled;

  bool get usagePermissionGranted => _usagePermissionGranted;

  bool get isCheckingPermission => _isCheckingPermission;

  DataExportStatus get exportStatus => _exportStatus;

  bool get isExporting => _exportStatus == DataExportStatus.running;

  String? get exportMessage => _exportMessage;

  String? get errorMessage => _errorMessage;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Memuat preferensi milik akun aktif.
  ///
  /// Preferensi tidak diwariskan antar akun: saat UID berubah state direset ke
  /// nilai bawaan sebelum data akun baru dibaca.
  Future<void> loadForUser(String? uid) async {
    if (_userId == uid) return;

    _userId = uid;
    final requestId = ++_requestId;

    _notificationsEnabled = true;
    _exportStatus = DataExportStatus.idle;
    _exportMessage = null;
    _errorMessage = null;
    _notify();

    if (uid == null) {
      await refreshUsagePermission();
      return;
    }

    final setting = await _readSetting(uid);

    if (_disposed || requestId != _requestId || _userId != uid) return;

    _notificationsEnabled = setting?.notificationsEnabled ?? true;
    _notify();

    await refreshUsagePermission();
  }

  /// Menyimpan preferensi notifikasi aplikasi.
  Future<void> setNotificationsEnabled(bool enabled) async {
    final uid = _userId;
    if (uid == null || _notificationsEnabled == enabled) return;

    final previous = _notificationsEnabled;
    _notificationsEnabled = enabled;
    _errorMessage = null;
    _notify();

    try {
      await _settingsRepository.updateNotifications(
        uid,
        enabled: enabled,
        updatedAt: DateTime.now(),
      );
    } catch (error, stack) {
      debugPrint(
        '[DATAWISE settings] gagal menyimpan preferensi notifikasi: $error',
      );
      debugPrintStack(stackTrace: stack, label: '[DATAWISE settings]');

      if (_disposed || _userId != uid) return;

      _notificationsEnabled = previous;
      _errorMessage = 'Preferensi notifikasi gagal disimpan.';
      _notify();
    }
  }

  /// Membaca ulang izin Usage Access Android yang sebenarnya.
  Future<void> refreshUsagePermission() async {
    if (_isCheckingPermission) return;

    _isCheckingPermission = true;
    _notify();

    final granted = await _usageService.hasPermission();

    if (_disposed) return;

    _usagePermissionGranted = granted;
    _isCheckingPermission = false;
    _notify();
  }

  /// Membuka halaman Usage Access Android, lalu memeriksa ulang statusnya.
  ///
  /// Pemeriksaan setelah kembali ke aplikasi dilakukan pemanggil melalui
  /// [refreshUsagePermission] saat lifecycle resumed.
  Future<void> requestUsagePermission() async {
    await _usageService.openUsageAccessSettings();
    await refreshUsagePermission();
  }

  /// Membuka pengaturan internet Android melalui UsageService yang sudah
  /// tersedia (MethodChannel `datawise/usage`).
  Future<void> openInternetSettings() => _usageService.openInternetSettings();

  /// Membuat dan membagikan backup milik akun aktif.
  Future<void> exportData() async {
    if (_exportStatus == DataExportStatus.running) return;

    final uid = _userId;

    if (uid == null) {
      _exportStatus = DataExportStatus.failure;
      _exportMessage = null;
      _errorMessage = 'Masuk ke akun untuk mengekspor data.';
      _notify();
      return;
    }

    _exportStatus = DataExportStatus.running;
    _exportMessage = null;
    _errorMessage = null;
    _notify();

    try {
      final result = await _exportService.exportAndShare(uid);

      if (_disposed || _userId != uid) return;

      _exportStatus = DataExportStatus.success;
      _exportMessage = result.isEmpty
          ? 'Belum ada data untuk diekspor. Berkas backup kosong tetap dibuat.'
          : 'Backup berisi ${result.totalRows} baris data berhasil dibuat dan '
                'dibagikan.';
    } catch (error, stack) {
      debugPrint('[DATAWISE export] gagal mengekspor data: $error');
      debugPrintStack(stackTrace: stack, label: '[DATAWISE export]');

      if (_disposed || _userId != uid) return;

      _exportStatus = DataExportStatus.failure;
      _errorMessage = 'Gagal mengekspor data. Coba lagi.';
    }

    _notify();
  }

  Future<UserSetting?> _readSetting(String uid) async {
    try {
      return await _settingsRepository.getByUserId(uid);
    } catch (error, stack) {
      debugPrint('[DATAWISE settings] gagal membaca pengaturan: $error');
      debugPrintStack(stackTrace: stack, label: '[DATAWISE settings]');
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
