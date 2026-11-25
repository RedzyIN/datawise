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
import 'dashboard_data_limit_calculator.dart';
import 'local_notification_service.dart';
import 'planner_service.dart';
import 'usage_totals.dart';

enum DataLimitStatus { normal, warning, reached, exceeded, noLimit, disabled }

class DataLimitEvaluation {
  final int usedBytes;
  final int? limitBytes;
  final double? usagePercent;
  final DataLimitStatus status;
  final AlertType? alertType;

  /// Dari mana angka [limitBytes] berasal: batas manual pengguna, fallback
  /// target harian Data Planner, atau tidak ada sama sekali.
  final DataLimitSource limitSource;

  /// Target harian Data Planner (null bila tidak dapat dihitung). Dipakai UI
  /// untuk menjelaskan fallback tanpa menghitung ulang rumus planner.
  final double? plannerDailyTargetBytes;

  const DataLimitEvaluation({
    required this.usedBytes,
    required this.limitBytes,
    required this.usagePercent,
    required this.status,
    required this.alertType,
    this.limitSource = DataLimitSource.none,
    this.plannerDailyTargetBytes,
  });

  int? get remainingBytes =>
      limitBytes == null ? null : limitBytes! - usedBytes;

  bool get usesPlannerTarget => limitSource == DataLimitSource.planner;

  bool get usesManualLimit => limitSource == DataLimitSource.manual;
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

  /// Ambang peringatan bawaan bila pengguna belum mengubahnya.
  static const int defaultWarnAtPercent = 80;

  /// Ambang batas bawaan (tidak dapat diturunkan lewat UI).
  static const int defaultLimitAtPercent = 100;

  // Menyimpan batas pemakaian harian.
  Future<void> saveDailyLimit(DataLimitSetting setting) async {
    await _dataLimitRepo.upsert(setting);
  }

  // Mengambil pengaturan batas pemakaian suatu paket.
  Future<DataLimitSetting?> getDailyLimit(String packageId) async {
    return _dataLimitRepo.getByPackage(packageId);
  }

  // Menghapus pengaturan batas sebuah paket sehingga fallback Data Planner
  // kembali dipakai.
  Future<void> clearDailyLimit(String packageId) async {
    await _dataLimitRepo.delete(packageId);
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

  /// Target harian Data Planner untuk paket ini berdasarkan catatan pemakaian
  /// yang tersimpan (bukan angka dari paket lain).
  ///
  /// Dipakai halaman Data Limit, Provider, dan worker background agar angka
  /// fallback selalu berasal dari satu perhitungan.
  Future<PlannerResult> plannerResultFor(
    DataPackage package, {
    DateTime? now,
  }) async {
    final packageId = package.id;

    if (packageId == null || packageId.isEmpty) {
      throw const AppException(
        AppException.validation,
        'Paket belum memiliki ID.',
      );
    }

    final today = dateOnly(now ?? DateTime.now());
    final records = await _usageRepo.getRecords(packageId);
    final byDay = effectiveUsageRecordsByDay(records);

    var totalUsed = 0;
    for (final dayRecords in byDay.values) {
      for (final record in dayRecords) {
        totalUsed += record.totalBytes;
      }
    }

    final todayRecords = byDay[today] ?? const <UsageRecord>[];
    final todayUsed = todayRecords.fold<int>(
      0,
      (sum, record) => sum + record.totalBytes,
    );

    return PlannerService.calculate(
      package: package,
      totalUsedBytes: totalUsed,
      todayUsedBytes: todayUsed,
      today: today,
    );
  }

  /// Target harian planner yang boleh dipakai sebagai batas fallback.
  ///
  /// Paket kedaluwarsa atau belum berjalan tidak memiliki sisa hari yang valid,
  /// sehingga tidak boleh memicu evaluasi notifikasi.
  int? _plannerTargetFrom(PlannerResult? result) {
    if (result == null) return null;

    if (result.status == PlannerStatus.expired ||
        result.status == PlannerStatus.notStarted) {
      return null;
    }

    final target = result.dailyTargetBytes;

    if (target == null || !target.isFinite || target <= 0) return null;

    final rounded = target.round();

    return rounded > 0 ? rounded : null;
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
    final plannerTarget = _plannerTargetFrom(plannerResult);

    if (setting != null && !setting.isEnabled) {
      return DataLimitEvaluation(
        usedBytes: usedBytes,
        limitBytes: setting.dailyLimitBytes,
        usagePercent: null,
        status: DataLimitStatus.disabled,
        alertType: null,
        // Tidak ada batas yang sedang berlaku; batas tersimpan tetap dibawa
        // untuk ditampilkan, sama seperti di DashboardDataLimitCalculator.
        limitSource: DataLimitSource.none,
        plannerDailyTargetBytes: plannerTarget?.toDouble(),
      );
    }

    // Gunakan batas khusus pengguna jika tersedia dan valid.
    // Jika tidak, gunakan target harian dari Data Planner.
    final manualLimit = setting?.dailyLimitBytes;
    final validManual = manualLimit != null && manualLimit > 0
        ? manualLimit
        : null;

    final int? limitBytes = validManual ?? plannerTarget;

    final DataLimitSource source = validManual != null
        ? DataLimitSource.manual
        : plannerTarget != null
        ? DataLimitSource.planner
        : DataLimitSource.none;

    if (limitBytes == null || limitBytes <= 0) {
      return DataLimitEvaluation(
        usedBytes: usedBytes,
        limitBytes: null,
        usagePercent: null,
        status: DataLimitStatus.noLimit,
        alertType: null,
        limitSource: source,
        plannerDailyTargetBytes: plannerTarget?.toDouble(),
      );
    }

    final double percentage = (usedBytes / limitBytes) * 100;

    final int warningThreshold = setting?.warnAtPercent ?? defaultWarnAtPercent;
    final int limitThreshold = setting?.limitAtPercent ?? defaultLimitAtPercent;

    DataLimitEvaluation build(DataLimitStatus status, AlertType? alertType) =>
        DataLimitEvaluation(
          usedBytes: usedBytes,
          limitBytes: limitBytes,
          usagePercent: percentage,
          status: status,
          alertType: alertType,
          limitSource: source,
          plannerDailyTargetBytes: plannerTarget?.toDouble(),
        );

    // Pemakaian tepat pada ambang dihitung "tercapai"; di atasnya "terlampaui".
    if (percentage > limitThreshold) {
      return build(DataLimitStatus.exceeded, AlertType.dailyOver);
    }

    if (percentage >= limitThreshold) {
      return build(DataLimitStatus.reached, AlertType.daily100);
    }

    if (percentage >= warningThreshold) {
      return build(DataLimitStatus.warning, AlertType.daily80);
    }

    return build(DataLimitStatus.normal, null);
  }

  // Evaluasi + peringatan lokal. Kunci deduplikasi memakai paket, tanggal
  // lokal, dan jenis ambang sehingga notifikasi identik hanya terkirim sekali
  // per hari.
  //
  // Catatan penting: AlertLog TIDAK dihapus ketika notifikasi gagal tampil.
  // Dahulu log dihapus "agar dicoba lagi", tetapi itu membuat notifikasi yang
  // sama dibuat ulang pada setiap refresh (termasuk setelah pengguna
  // menggesernya dari notification shade). Riwayat kini dipertahankan, dan
  // deduplikasi notifikasi lokal memakai id yang stabil.
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

    // AlertLog sudah ada untuk kejadian hari ini: jangan kirim ulang.
    if (alertId == null) return evaluation;

    await _notifications.showWarning(
      id: alertNotificationId(
        packageId: packageId,
        type: alertType,
        date: triggeredAt,
      ),
      title: 'Peringatan Batas Data',
      body: message,
      payload: dedupeKey,
    );

    return evaluation;
  }

  String _warningMessage(DataLimitEvaluation evaluation) {
    final limit = evaluation.limitBytes == null
        ? '-'
        : formatBytes(evaluation.limitBytes!);
    final percent = (evaluation.usagePercent ?? 0).round();
    final source = evaluation.usesPlannerTarget ? ' (target Data Planner)' : '';

    return switch (evaluation.status) {
      DataLimitStatus.warning =>
        'Pemakaian data hari ini $percent% dari batas $limit$source. '
            'Segera kurangi pemakaian agar tidak melewati batas.',
      DataLimitStatus.reached =>
        'Batas penggunaan data harian $limit$source sudah tercapai ($percent%).',
      DataLimitStatus.exceeded =>
        'Pemakaian data hari ini $percent% dari batas $limit$source. '
            'Batas harian terlampaui.',
      _ => 'Pemakaian data hari ini $percent% dari batas $limit$source.',
    };
  }
}
