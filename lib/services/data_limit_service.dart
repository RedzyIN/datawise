// Layanan Data Limit Warning: menyimpan batas harian, mengevaluasi pemakaian,
// dan mengirim notifikasi 80%/100% tanpa duplikasi.
//
// Kalkulasi status ringkas untuk Dashboard berada di
// `dashboard_data_limit_calculator.dart` agar tanggung jawab kedua bagian tidak
// saling bergantung.
import '../core/format_utils.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import 'alert_dedupe.dart';
import 'local_notification_service.dart';

enum DataLimitStatus { normal, warning, reached, exceeded, noLimit, disabled }

class DataLimitEvaluation {
  final int usedBytes;
  final int? limitBytes;
  final double? usagePercent;
  final DataLimitStatus status;
  final AlertType? alertType;

  const DataLimitEvaluation({
    required this.usedBytes,
    required this.limitBytes,
    required this.usagePercent,
    required this.status,
    required this.alertType,
  });

  int? get remainingBytes =>
      limitBytes == null ? null : limitBytes! - usedBytes;
}

class DataLimitService {
  DataLimitService(
    this._dataLimitRepo,
    this._usageRepo,
    this._alertRepo,
    this._settingsRepo,
    this._notifications,
  );

  final DataLimitRepository _dataLimitRepo;
  final UsageRepository _usageRepo;
  final AlertRepository _alertRepo;
  final SettingsRepository _settingsRepo;
  final LocalNotificationService _notifications;

  // Menyimpan batas pemakaian harian.
  Future<void> saveDailyLimit(DataLimitSetting setting) async {
    await _dataLimitRepo.upsert(setting);
  }

  // Mengambil pengaturan batas pemakaian suatu paket.
  Future<DataLimitSetting?> getDailyLimit(String packageId) async {
    return _dataLimitRepo.getByPackage(packageId);
  }

  // Notifikasi hanya dikirim bila preferensi Settings aktif.
  Future<bool> notificationsEnabledFor(String userId) async {
    final setting = await _settingsRepo.getByUserId(userId);
    return setting?.notificationsEnabled ?? true;
  }

  // Pemakaian efektif satu hari. Manual menggantikan otomatis.
  // Urutan otomatis mengikuti PRD 5.4 dan DashboardProvider: DEVICE_TOTAL
  // lebih dulu, APP_USAGE hanya bila agregat perangkat tidak tersedia.
  // Keduanya tidak pernah dijumlahkan bersama.
  Future<int> usedBytesOn(String packageId, DateTime day) async {
    final start = dateOnly(day);
    final end = start.add(const Duration(days: 1));

    final records = await _usageRepo.getRecordsForPeriod(packageId, start, end);

    int totalOf(UsageRecordScope scope) => records
        .where(
          (record) =>
              record.recordScope == scope &&
              record.networkType != NetworkType.wifi,
        )
        .fold(0, (sum, record) => sum + record.totalBytes);

    final manual = totalOf(UsageRecordScope.manualTotal);
    if (manual > 0) return manual;

    final device = totalOf(UsageRecordScope.deviceTotal);
    if (device > 0) return device;

    return totalOf(UsageRecordScope.appUsage);
  }

  // Menghitung penggunaan dan menentukan status peringatan.
  Future<DataLimitEvaluation> evaluate({
    required String packageId,
    required int usedBytes,
    PlannerResult? plannerResult,
  }) async {
    if (usedBytes < 0) {
      throw ArgumentError('Pemakaian data tidak boleh negatif.');
    }

    final setting = await getDailyLimit(packageId);

    if (setting != null && !setting.isEnabled) {
      return DataLimitEvaluation(
        usedBytes: usedBytes,
        limitBytes: setting.dailyLimitBytes,
        usagePercent: null,
        status: DataLimitStatus.disabled,
        alertType: null,
      );
    }

    // Gunakan batas khusus pengguna jika tersedia.
    // Jika tidak, gunakan target harian dari Data Planner.
    final int? limitBytes =
        setting?.dailyLimitBytes ?? plannerResult?.dailyTargetBytes?.round();

    if (limitBytes == null || limitBytes <= 0) {
      return DataLimitEvaluation(
        usedBytes: usedBytes,
        limitBytes: null,
        usagePercent: null,
        status: DataLimitStatus.noLimit,
        alertType: null,
      );
    }

    final double percentage = (usedBytes / limitBytes) * 100;

    final int warningThreshold = setting?.warnAtPercent ?? 80;
    final int limitThreshold = setting?.limitAtPercent ?? 100;

    // Pemakaian tepat pada ambang dihitung "tercapai"; di atasnya "terlampaui".
    if (percentage > limitThreshold) {
      return DataLimitEvaluation(
        usedBytes: usedBytes,
        limitBytes: limitBytes,
        usagePercent: percentage,
        status: DataLimitStatus.exceeded,
        alertType: AlertType.dailyOver,
      );
    }

    if (percentage >= limitThreshold) {
      return DataLimitEvaluation(
        usedBytes: usedBytes,
        limitBytes: limitBytes,
        usagePercent: percentage,
        status: DataLimitStatus.reached,
        alertType: AlertType.daily100,
      );
    }

    if (percentage >= warningThreshold) {
      return DataLimitEvaluation(
        usedBytes: usedBytes,
        limitBytes: limitBytes,
        usagePercent: percentage,
        status: DataLimitStatus.warning,
        alertType: AlertType.daily80,
      );
    }

    return DataLimitEvaluation(
      usedBytes: usedBytes,
      limitBytes: limitBytes,
      usagePercent: percentage,
      status: DataLimitStatus.normal,
      alertType: null,
    );
  }

  // Evaluasi + peringatan lokal. Kunci deduplikasi memakai paket, tanggal
  // lokal, dan jenis ambang sehingga notifikasi identik hanya terkirim sekali
  // per hari.
  Future<DataLimitEvaluation> evaluateAndNotify({
    required String packageId,
    required String userId,
    required int usedBytes,
    PlannerResult? plannerResult,
    DateTime? now,
  }) async {
    final evaluation = await evaluate(
      packageId: packageId,
      usedBytes: usedBytes,
      plannerResult: plannerResult,
    );

    final alertType = evaluation.alertType;
    if (alertType == null) return evaluation;

    if (!await notificationsEnabledFor(userId)) return evaluation;

    final triggeredAt = now ?? DateTime.now();

    // Kunci deduplikasi sama dengan Smart Alerts sehingga ambang yang sama
    // tidak pernah dikirim dua kali oleh dua jalur evaluasi.
    final dedupeKey = alertDedupeKey(
      packageId: packageId,
      type: alertType,
      date: triggeredAt,
    );

    final message = _warningMessage(evaluation);

    final alertId = await _alertRepo.createIfAbsent(
      AlertLog(
        packageId: packageId,
        alertType: alertTypeToDb(alertType),
        message: message,
        observedBytes: usedBytes,
        thresholdBytes: evaluation.limitBytes,
        dedupeKey: dedupeKey,
        triggeredAt: triggeredAt,
        isRead: false,
      ),
    );

    if (alertId == null) return evaluation;

    final shown = await _notifications.showWarning(
      id: alertNotificationId(
        packageId: packageId,
        type: alertType,
        date: triggeredAt,
      ),
      title: 'Peringatan Batas Data',
      body: message,
      payload: dedupeKey,
    );

    if (!shown) {
      // Pemulihan: hapus riwayat agar evaluasi berikutnya mencoba lagi.
      await _alertRepo.delete(alertId);
    }

    return evaluation;
  }

  String _warningMessage(DataLimitEvaluation evaluation) {
    final limit = evaluation.limitBytes == null
        ? '-'
        : formatBytes(evaluation.limitBytes!);
    final percent = (evaluation.usagePercent ?? 0).round();

    return switch (evaluation.status) {
      DataLimitStatus.warning =>
        'Pemakaian data hari ini $percent% dari batas $limit. '
            'Segera kurangi pemakaian agar tidak melewati batas.',
      DataLimitStatus.reached =>
        'Batas penggunaan data harian $limit sudah tercapai ($percent%).',
      DataLimitStatus.exceeded =>
        'Pemakaian data hari ini $percent% dari batas $limit. '
            'Batas harian terlampaui.',
      _ => 'Pemakaian data hari ini $percent% dari batas $limit.',
    };
  }
}
