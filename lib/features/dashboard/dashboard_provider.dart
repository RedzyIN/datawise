// PEMILIK: Anggota D (Nero). Menggabungkan paket + pemakaian + planner + alert.
// Provider TIDAK menghitung rumus sendiri: target/sisa berasal dari PlannerService.
// Urutan refresh: getActive -> hasPermission -> refreshToday -> getTotalUsedBytes &
// getUsedBytesOn -> PlannerService.calculate -> evaluateAndNotify -> notifyListeners.
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../../services/alert_service.dart';
import '../../services/planner_service.dart';
import '../../services/usage_service.dart';

enum DashboardLoad { loading, ready, noPackage, error }

class DashboardProvider extends ChangeNotifier {
  DashboardProvider(
    this._packageRepo,
    this._usageRepo,
    this._usageService,
    this._alertService,
  );

  final PackageRepository _packageRepo;
  final UsageRepository _usageRepo;
  final UsageService _usageService;
  final AlertService _alertService;

  DashboardLoad loadState = DashboardLoad.loading;
  DataPackage? package;
  PlannerResult? plan;
  List<UsageRecord> records = const [];

  /// Pemakaian efektif per tanggal (manual menggantikan auto), untuk grafik 7 hari.
  Map<DateTime, int> dailyUsage = const {};
  String? errorMessage;

  /// Total terpakai (sudah termasuk initial_used_bytes), langsung dari repository.
  int totalUsedBytes = 0;

  /// Status izin Usage Access terakhir yang diperiksa.
  bool hasPermission = false;

  /// Hasil pembacaan Android terakhir (null jika belum pernah/izin belum ada).
  UsageReading? lastReading;

  /// Waktu terakhir statistik berhasil dimutakhirkan.
  DateTime? lastUpdatedAt;

  /// true jika PlannerService belum bisa menghitung (mis. belum diimplementasikan
  /// atau melempar error). Dashboard tetap menampilkan paket & pemakaian.
  bool planUnavailable = false;

  int _generation = 0;
  bool _notifPermissionAsked = false;
  bool _disposed = false;

  Future<void> refresh(String userId) async {
    final gen = ++_generation;
    // Jangan tampilkan spinner penuh jika data lama sudah ada (pull-to-refresh).
    if (package == null) {
      loadState = DashboardLoad.loading;
      _notify();
    }

    try {
      final active = await _packageRepo.getActive(userId);
      if (gen != _generation) return;

      if (active == null || active.id == null) {
        package = null;
        plan = null;
        records = const [];
        dailyUsage = const {};
        totalUsedBytes = 0;
        planUnavailable = false;
        errorMessage = null;
        hasPermission = await _usageService.hasPermission();
        loadState = DashboardLoad.noPackage;
        _notify();
        return;
      }

      final packageId = active.id!;

      // Android 13+: izin notifikasi diminta sekali, agar peringatan kuota bisa tampil.
      if (!_notifPermissionAsked) {
        _notifPermissionAsked = true;
        try {
          await _alertService.requestPermission();
        } catch (_) {}
      }
      hasPermission = await _usageService.hasPermission();

      // UsageService tidak pernah melempar error; kegagalan ada di reading.status.
      if (hasPermission) {
        final reading = await _usageService.refreshToday(active);
        lastReading = reading;
        if (reading.status == UsageReadStatus.ok) lastUpdatedAt = DateTime.now();
      } else {
        lastReading = null;
      }
      if (gen != _generation) return;

      final today = dateOnly(DateTime.now());
      final loadedRecords = await _usageRepo.getRecords(packageId);
      final totalUsed = await _usageRepo.getTotalUsedBytes(packageId);
      final todayUsed = await _usageRepo.getUsedBytesOn(packageId, today);
      final loadedDaily = await _usageRepo.getDailyUsage(packageId);
      if (gen != _generation) return;

      PlannerResult? result;
      var unavailable = false;
      try {
        result = PlannerService.calculate(
          package: active,
          totalUsedBytes: totalUsed,
          todayUsedBytes: todayUsed,
          today: today,
        );
      } on UnimplementedError {
        unavailable = true; // PlannerService (Anggota B) belum selesai.
      } catch (_) {
        unavailable = true;
      }

      if (result != null) {
        try {
          await _alertService.evaluateAndNotify(active, result);
        } catch (_) {
          // Kegagalan notifikasi tidak boleh merusak Dashboard.
        }
      }

      package = active;
      records = loadedRecords;
      dailyUsage = loadedDaily;
      totalUsedBytes = totalUsed;
      plan = result;
      planUnavailable = unavailable;
      errorMessage = null;
      loadState = DashboardLoad.ready;
      _notify();
    } on AppException catch (e) {
      if (gen != _generation) return;
      errorMessage = e.message;
      loadState = DashboardLoad.error;
      _notify();
    } catch (_) {
      if (gen != _generation) return;
      errorMessage = 'Terjadi kesalahan saat memuat Dashboard.';
      loadState = DashboardLoad.error;
      _notify();
    }
  }

  /// Dipanggil saat aplikasi kembali ke depan: izin bisa berubah di Pengaturan Android.
  Future<void> recheckPermission() async {
    final granted = await _usageService.hasPermission();
    if (granted != hasPermission) {
      hasPermission = granted;
      _notify();
    }
  }

  Future<void> openUsageAccessSettings() => _usageService.openUsageAccessSettings();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
