import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';

abstract class AlertService {
  Future<void> init();
  Future<bool> requestPermission();

  Future<void> evaluateAndNotify(
    String userId,
    DataPackage package,
    PlannerResult result,
  );
}

abstract class NotificationSink {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> show(int id, String title, String body);
}

class LocalNotificationSink implements NotificationSink {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'datawise_alerts';
  static const _channelName = 'Peringatan kuota';

  @override
  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Peringatan target, sisa kuota, dan masa aktif paket',
            importance: Importance.high,
          ),
        );
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> show(int id, String title, String body) {
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
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

  String _dedupeKey(String packageId, AlertType type, DateTime date) {
    final day = dateOnly(date).toIso8601String().split('T').first;
    return '$packageId:${type.name}:$day';
  }

  int _notificationId(String packageId, AlertType type, DateTime date) {
    return Object.hash(packageId, type.index, date.year, date.month, date.day) &
        0x7fffffff;
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

    final candidates =
        <
          ({
            AlertType type,
            DateTime date,
            String title,
            String body,
            int? observedBytes,
            int? thresholdBytes,
            String? categoryId,
          })
        >[];

    // Smart Alert: kuota MAIN tersisa 20% atau kurang.
    final mainQuota = await _getMainQuota(packageId);

    if (mainQuota != null &&
        mainQuota.remainingBytes * 100 <=
            mainQuota.category.capacityBytes * 20) {
      candidates.add((
        type: AlertType.quota10,
        date: today,
        title: 'Sisa kuota utama menipis',
        body:
            'Sisa kuota utama ${package.packageName} tinggal 20% atau kurang.',
        observedBytes: mainQuota.remainingBytes,
        thresholdBytes: (mainQuota.category.capacityBytes * 0.2).round(),
        categoryId: mainQuota.category.id,
      ));
    }

    // Smart Alert: target harian tercapai atau terlampaui.
    final pct = result.todayPercentOfTarget;

    if (pct != null) {
      if (pct > 100.5) {
        candidates.add((
          type: AlertType.dailyOver,
          date: today,
          title: 'Target harian terlampaui',
          body:
              'Pemakaian hari ini melewati target harian ${package.packageName}.',
          observedBytes: result.todayUsedBytes,
          thresholdBytes: result.dailyTargetBytes?.round(),
          categoryId: null,
        ));
      } else if (pct >= 100) {
        candidates.add((
          type: AlertType.daily100,
          date: today,
          title: 'Target harian tercapai',
          body:
              'Pemakaian hari ini sudah mencapai target harian ${package.packageName}.',
          observedBytes: result.todayUsedBytes,
          thresholdBytes: result.dailyTargetBytes?.round(),
          categoryId: null,
        ));
      }
    }

    // Smart Alert: paket berakhir satu hari kalender sebelum end_date.
    if (today == dateOnly(package.endDate).subtract(const Duration(days: 1))) {
      candidates.add((
        type: AlertType.expiring1d,
        date: today,
        title: 'Paket berakhir besok',
        body: '${package.packageName} akan berakhir besok.',
        observedBytes: null,
        thresholdBytes: null,
        categoryId: null,
      ));
    }

    if (candidates.isEmpty) return;

    await init();

    for (final candidate in candidates) {
      final key = _dedupeKey(packageId, candidate.type, candidate.date);

      if (await _alertRepo.existsByDedupeKey(key)) continue;

      try {
        await _alertRepo.add(
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

        await _sink.show(
          _notificationId(packageId, candidate.type, candidate.date),
          candidate.title,
          candidate.body,
        );
      } catch (_) {
        // Kegagalan notifikasi tidak boleh menggagalkan Dashboard.
      }
    }
  }
}
