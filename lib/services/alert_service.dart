// Smart Alerts DATAWISE (Kiki): evaluasi aturan, deduplikasi, riwayat, dan
// notifikasi lokal.
//
// Arsitektur: UI -> Provider -> AlertService -> AlertRepository (SQLite).
// Service ini hanya memakai repository; tidak ada akses database langsung.
import '../core/format_utils.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import 'alert_dedupe.dart';
import 'local_notification_service.dart';

abstract class AlertService {
  Future<void> init();
  Future<bool> requestPermission();

  Future<void> evaluateAndNotify(
    String userId,
    DataPackage package,
    PlannerResult result,
  );
}

/// Saluran notifikasi yang dapat diganti saat pengujian.
abstract class NotificationSink {
  Future<void> init();
  Future<bool> requestPermission();

  /// Mengembalikan `true` bila notifikasi benar-benar ditampilkan.
  Future<bool> show(int id, String title, String body);
}

/// [NotificationSink] yang memakai infrastruktur notifikasi lokal bersama.
///
/// Dengan begitu Smart Alerts dan Data Limit Warning memakai satu plugin,
/// satu inisialisasi, dan satu alur izin POST_NOTIFICATIONS.
class LocalNotificationSink implements NotificationSink {
  LocalNotificationSink([LocalNotificationService? service])
    : _service = service ?? FlutterLocalNotificationService();

  final LocalNotificationService _service;

  @override
  Future<void> init() async {
    await _service.init();
  }

  @override
  Future<bool> requestPermission() => _service.requestPermission();

  @override
  Future<bool> show(int id, String title, String body) {
    return _service.showAlert(id: id, title: title, body: body);
  }
}

/// Kandidat alert yang lolos aturan sebelum disimpan.
class _AlertCandidate {
  const _AlertCandidate({
    required this.type,
    required this.date,
    required this.title,
    required this.body,
    this.observedBytes,
    this.thresholdBytes,
    this.categoryId,
  });

  final AlertType type;
  final DateTime date;
  final String title;
  final String body;
  final int? observedBytes;
  final int? thresholdBytes;
  final String? categoryId;
}

class AlertServiceImpl implements AlertService {
  AlertServiceImpl(
    this._alertRepo,
    this._settingsRepo, {
    required this._categoryRepo,
    required this._usageRepo,
    NotificationSink? sink,
    DateTime Function()? now,
  }) : _sink = sink ?? LocalNotificationSink(),
       _now = now ?? DateTime.now;

  final AlertRepository _alertRepo;
  final SettingsRepository _settingsRepo;
  final QuotaCategoryRepository _categoryRepo;
  final UsageRepository _usageRepo;
  final NotificationSink _sink;
  final DateTime Function() _now;

  /// Ambang peringatan target harian (persen).
  static const int dailyWarningPercent = 80;

  /// Ambang sisa kuota utama (persen dari kapasitas kategori MAIN).
  static const int mainQuotaWarningPercent = 20;

  Future<void>? _initFuture;

  @override
  Future<void> init() => _initFuture ??= _sink.init();

  @override
  Future<bool> requestPermission() async {
    await init();
    return _sink.requestPermission();
  }

  Future<bool> _enabled(String userId) async {
    final setting = await _settingsRepo.getByUserId(userId);
    return setting?.notificationsEnabled ?? true;
  }

  Future<({QuotaCategory category, int remainingBytes})?> _getMainQuota(
    String packageId,
  ) async {
    final categories = await _categoryRepo.getByPackage(packageId);

    final mainCategories = categories.where(
      (category) =>
          category.categoryType == QuotaCategoryType.main && category.isEnabled,
    );

    if (mainCategories.isEmpty) return null;

    final main = mainCategories.first;
    final categoryId = main.id;

    if (categoryId == null || main.capacityBytes <= 0) return null;

    final allocations = await _usageRepo.getAllocationsByPackage(packageId);

    final usedBytes = allocations
        .where((allocation) => allocation.quotaCategoryId == categoryId)
        .fold<int>(0, (total, allocation) => total + allocation.allocatedBytes);

    final remainingBytes = (main.capacityBytes - usedBytes).clamp(
      0,
      main.capacityBytes,
    );

    return (category: main, remainingBytes: remainingBytes);
  }

  List<_AlertCandidate> _buildCandidates({
    required DataPackage package,
    required PlannerResult result,
    required DateTime today,
    required ({QuotaCategory category, int remainingBytes})? mainQuota,
  }) {
    final candidates = <_AlertCandidate>[];

    // Aturan 1: sisa kuota kategori MAIN 20% atau kurang.
    if (mainQuota != null) {
      final capacityBytes = mainQuota.category.capacityBytes;
      final remainingBytes = mainQuota.remainingBytes;

      if (remainingBytes * 100 <= capacityBytes * mainQuotaWarningPercent) {
        final remainingPercent = (remainingBytes * 100 / capacityBytes).round();

        candidates.add(
          _AlertCandidate(
            type: AlertType.quota20,
            date: today,
            title: 'Sisa kuota utama menipis',
            body:
                'Sisa kuota utama ${package.packageName} tinggal '
                '$remainingPercent% (${formatBytes(remainingBytes)}).',
            observedBytes: remainingBytes,
            thresholdBytes: (capacityBytes * mainQuotaWarningPercent / 100)
                .round(),
            categoryId: mainQuota.category.id,
          ),
        );
      }
    }

    // Aturan 2: target harian 80%, tercapai (100%), atau terlampaui (>100%).
    final pct = result.todayPercentOfTarget;

    if (pct != null) {
      final actualPercent = pct.round();

      if (pct > 100) {
        candidates.add(
          _AlertCandidate(
            type: AlertType.dailyOver,
            date: today,
            title: 'Target harian terlampaui',
            body:
                'Pemakaian hari ini $actualPercent% dari target harian '
                '${package.packageName}. Target terlampaui.',
            observedBytes: result.todayUsedBytes,
            thresholdBytes: result.dailyTargetBytes?.round(),
          ),
        );
      } else if (pct >= 100) {
        candidates.add(
          _AlertCandidate(
            type: AlertType.daily100,
            date: today,
            title: 'Target harian tercapai',
            body:
                'Pemakaian hari ini sudah mencapai target harian '
                '${package.packageName} ($actualPercent%).',
            observedBytes: result.todayUsedBytes,
            thresholdBytes: result.dailyTargetBytes?.round(),
          ),
        );
      } else if (pct >= dailyWarningPercent) {
        candidates.add(
          _AlertCandidate(
            type: AlertType.daily80,
            date: today,
            title: 'Pemakaian target harian 80%',
            body:
                'Pemakaian hari ini $actualPercent% dari target harian '
                '${package.packageName}.',
            observedBytes: result.todayUsedBytes,
            thresholdBytes: result.dailyTargetBytes?.round(),
          ),
        );
      }
    }

    // Aturan 3: paket berakhir satu hari kalender sebelum end_date.
    final expiringDate = dateOnly(package.endDate)
        .subtract(const Duration(days: 1));

    if (today == expiringDate) {
      candidates.add(
        _AlertCandidate(
          type: AlertType.expiring1d,
          date: today,
          title: 'Paket berakhir besok',
          body: '${package.packageName} akan berakhir besok.',
        ),
      );
    }

    return candidates;
  }

  @override
  Future<void> evaluateAndNotify(
    String userId,
    DataPackage package,
    PlannerResult result,
  ) async {
    final packageId = package.id;

    if (packageId == null || packageId.isEmpty) return;
    if (!await _enabled(userId)) return;

    if (result.status == PlannerStatus.expired ||
        result.status == PlannerStatus.notStarted) {
      return;
    }

    final today = dateOnly(_now());

    final mainQuota = await _getMainQuota(packageId);

    final candidates = _buildCandidates(
      package: package,
      result: result,
      today: today,
      mainQuota: mainQuota,
    );

    if (candidates.isEmpty) return;

    await init();

    for (final candidate in candidates) {
      final key = alertDedupeKey(
        packageId: packageId,
        type: candidate.type,
        date: candidate.date,
      );

      // Penyimpanan lebih dulu, lalu notifikasi. UNIQUE(dedupe_key) di SQLite
      // membuat dua evaluasi yang berjalan hampir bersamaan tetap aman:
      // hanya satu yang mendapat id baru.
      final alertId = await _alertRepo.createIfAbsent(
        AlertLog(
          packageId: packageId,
          quotaCategoryId: candidate.categoryId,
          alertType: alertTypeToDb(candidate.type),
          message: candidate.body,
          observedBytes: candidate.observedBytes,
          thresholdBytes: candidate.thresholdBytes,
          dedupeKey: key,
          triggeredAt: _now(),
          isRead: false,
        ),
      );

      if (alertId == null) continue;

      var shown = false;

      try {
        shown = await _sink.show(
          alertNotificationId(
            packageId: packageId,
            type: candidate.type,
            date: candidate.date,
          ),
          candidate.title,
          candidate.body,
        );
      } catch (_) {
        shown = false;
      }

      if (!shown) {
        // Pemulihan: alert yang notifikasinya gagal tidak boleh menahan
        // deduplikasi selamanya. Hapus agar evaluasi berikutnya mencoba lagi.
        try {
          await _alertRepo.delete(alertId);
        } catch (_) {
          // Gagal membersihkan tidak boleh menggagalkan Dashboard.
        }
      }
    }
  }
}
