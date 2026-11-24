import 'package:datawise/features/alerts/alert_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/alert_repository.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingAlertRepository implements AlertRepository {
  @override
  Future<List<AlertLog>> getByPackage(String packageId) async {
    throw const AppException(AppException.dbError, 'Database tidak tersedia.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const userId = 'user-1';

  late InMemoryPackageRepository packages;
  late InMemoryAlertRepository alerts;
  late AlertProvider provider;

  setUp(() {
    packages = InMemoryPackageRepository();
    alerts = InMemoryAlertRepository(packages);
    provider = AlertProvider(alerts, packages);
  });

  Future<String> addPackage(String name) {
    final now = DateTime.now();

    return packages.add(
      DataPackage(
        userId: userId,
        packageName: name,
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10000000000,
        startDate: dateOnly(now.subtract(const Duration(days: 5))),
        endDate: dateOnly(now.add(const Duration(days: 20))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> addAlert({
    required String packageId,
    required AlertType type,
    required DateTime at,
    String message = 'Pesan alert',
    bool isRead = false,
  }) async {
    await alerts.createIfAbsent(
      AlertLog(
        packageId: packageId,
        alertType: alertTypeToDb(type),
        message: message,
        dedupeKey: '$packageId:${type.name}:${dateToDb(at)}',
        triggeredAt: at,
        isRead: isRead,
      ),
    );
  }

  test('tanpa riwayat alert menghasilkan daftar kosong', () async {
    await addPackage('Paket A');

    await provider.load(userId);

    expect(provider.loadState, AlertHistoryLoad.ready);
    expect(provider.isEmpty, isTrue);
    expect(provider.unreadCount, 0);
  });

  test('alert baru muncul pada riwayat dan diurutkan terbaru', () async {
    final packageId = await addPackage('Paket A');

    await addAlert(
      packageId: packageId,
      type: AlertType.daily100,
      at: DateTime(2026, 11, 16, 8, 30),
      message: 'Target harian tercapai',
    );
    await addAlert(
      packageId: packageId,
      type: AlertType.quota20,
      at: DateTime(2026, 11, 17, 9, 15),
      message: 'Sisa kuota utama menipis',
    );

    await provider.load(userId);

    expect(provider.entries, hasLength(2));
    expect(provider.entries.first.alert.message, 'Sisa kuota utama menipis');
    expect(provider.entries.last.alert.message, 'Target harian tercapai');
    expect(provider.entries.first.packageName, 'Paket A');
    expect(provider.unreadCount, 2);
  });

  test('markRead mengubah status baca di repository', () async {
    final packageId = await addPackage('Paket A');

    await addAlert(
      packageId: packageId,
      type: AlertType.dailyOver,
      at: DateTime(2026, 11, 17, 10),
    );

    await provider.load(userId);

    final alertId = provider.entries.single.alert.id!;

    expect(await provider.markRead(alertId), isTrue);

    expect(provider.entries.single.alert.isRead, isTrue);
    expect(provider.unreadCount, 0);

    final stored = await alerts.getByPackage(packageId);
    expect(stored.single.isRead, isTrue);
  });

  test('markAllRead hanya menandai paket terkait', () async {
    final firstPackage = await addPackage('Paket A');
    final secondPackage = await addPackage('Paket B');

    await addAlert(
      packageId: firstPackage,
      type: AlertType.daily100,
      at: DateTime(2026, 11, 16, 8),
    );
    await addAlert(
      packageId: firstPackage,
      type: AlertType.quota20,
      at: DateTime(2026, 11, 16, 9),
    );
    await addAlert(
      packageId: secondPackage,
      type: AlertType.expiring1d,
      at: DateTime(2026, 11, 17, 9),
    );

    await provider.load(userId);

    expect(await provider.markAllReadForPackage(firstPackage), isTrue);

    expect(provider.unreadCount, 1);

    final firstLogs = await alerts.getByPackage(firstPackage);
    expect(firstLogs.every((log) => log.isRead), isTrue);

    final secondLogs = await alerts.getByPackage(secondPackage);
    expect(secondLogs.single.isRead, isFalse);
  });

  test('markAllRead menandai semua paket', () async {
    final firstPackage = await addPackage('Paket A');
    final secondPackage = await addPackage('Paket B');

    await addAlert(
      packageId: firstPackage,
      type: AlertType.daily100,
      at: DateTime(2026, 11, 16, 8),
    );
    await addAlert(
      packageId: secondPackage,
      type: AlertType.expiring1d,
      at: DateTime(2026, 11, 17, 9),
    );

    await provider.load(userId);
    expect(provider.unreadCount, 2);

    expect(await provider.markAllRead(), isTrue);
    expect(provider.unreadCount, 0);
  });

  test('kegagalan repository menghasilkan state error', () async {
    await addPackage('Paket A');

    final failing = AlertProvider(_ThrowingAlertRepository(), packages);

    await failing.load(userId);

    expect(failing.loadState, AlertHistoryLoad.error);
    expect(failing.errorMessage, 'Database tidak tersedia.');
  });
}
