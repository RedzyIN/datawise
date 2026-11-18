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
            description:
                'Peringatan target harian, sisa kuota, dan masa aktif paket',
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
    NotificationSink? sink,
    DateTime Function()? now,
  }) : _sink = sink ?? LocalNotificationSink(),
       _now = now ?? DateTime.now;

  final AlertRepository _alertRepo;
  final SettingsRepository _settingsRepo;
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

    // Jika belum ada pengaturan, notifikasi aktif secara default.
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
          })
        >[];

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
        ));
      } else if (pct >= 80) {
        candidates.add((
          type: AlertType.daily80,
          date: today,
          title: 'Mendekati target harian',
          body:
              'Pemakaian hari ini sudah 80% dari target harian ${package.packageName}.',
          observedBytes: result.todayUsedBytes,
          thresholdBytes: result.dailyTargetBytes?.round(),
        ));
      }
    }

    if (result.totalBytes > 0 &&
        result.remainingBytes * 100 <= result.totalBytes * 10) {
      candidates.add((
        type: AlertType.quota10,
        date: dateOnly(package.endDate),
        title: 'Sisa kuota menipis',
        body: 'Sisa kuota ${package.packageName} tinggal 10% atau kurang.',
        observedBytes: result.remainingBytes,
        thresholdBytes: (result.totalBytes * 0.1).round(),
      ));
    }

    if (today == dateOnly(package.endDate).subtract(const Duration(days: 1))) {
      candidates.add((
        type: AlertType.expiring1d,
        date: today,
        title: 'Paket berakhir besok',
        body: '${package.packageName} akan berakhir besok.',
        observedBytes: null,
        thresholdBytes: null,
      ));
    }

    if (candidates.isEmpty) return;

    await init();

    for (final candidate in candidates) {
      final key = _dedupeKey(packageId, candidate.type, candidate.date);

      if (await _alertRepo.existsByDedupeKey(key)) continue;

      try {
        await _sink.show(
          _notificationId(packageId, candidate.type, candidate.date),
          candidate.title,
          candidate.body,
        );

        await _alertRepo.add(
          AlertLog(
            packageId: packageId,
            alertType: alertTypeToDb(candidate.type),
            message: candidate.body,
            observedBytes: candidate.observedBytes,
            thresholdBytes: candidate.thresholdBytes,
            dedupeKey: key,
            triggeredAt: _now(),
            isRead: false,
          ),
        );
      } catch (_) {
        // Jika gagal, jangan membuat catatan dedupe.
      }
    }
  }
}
