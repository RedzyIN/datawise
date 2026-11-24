import 'package:datawise/core/db_helper.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/sqlite/sqlite_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const userId = 'user-alert';

  late DbHelper helper;
  late SqlitePackageRepository packages;
  late SqliteAlertRepository alerts;
  late String packageId;

  final today = DateTime(2026, 11, 17, 9);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    const path = 'datawise_alert_repository_test.db';
    await databaseFactory.deleteDatabase(path);

    helper = DbHelper.forTesting(path);
    packages = SqlitePackageRepository(helper);
    alerts = SqliteAlertRepository(helper);

    final db = await helper.database;

    await db.insert('users', {
      'id': userId,
      'display_name': 'Pengguna Alert',
      'email': 'alert@example.com',
      'created_at': today.toIso8601String(),
      'updated_at': today.toIso8601String(),
    });

    final now = DateTime.now();

    packageId = await packages.add(
      DataPackage(
        userId: userId,
        packageName: 'Paket SQLite',
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10000000000,
        startDate: dateOnly(now.subtract(const Duration(days: 3))),
        endDate: dateOnly(now.add(const Duration(days: 20))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await helper.close();
  });

  AlertLog log({
    required AlertType type,
    required DateTime at,
    String message = 'Pesan alert SQLite',
    bool isRead = false,
  }) {
    return AlertLog(
      packageId: packageId,
      alertType: alertTypeToDb(type),
      message: message,
      observedBytes: 1500000000,
      thresholdBytes: 2000000000,
      dedupeKey: '$packageId:${type.name}:${dateToDb(at)}',
      triggeredAt: at,
      isRead: isRead,
    );
  }

  test('alert baru tersimpan di SQLite', () async {
    final id = await alerts.createIfAbsent(
      log(type: AlertType.quota20, at: today),
    );

    expect(id, isNotNull);

    final stored = await alerts.getByPackage(packageId);

    expect(stored, hasLength(1));
    expect(stored.single.alertType, 'QUOTA20');
    expect(stored.single.message, 'Pesan alert SQLite');
    expect(stored.single.isRead, isFalse);
    expect(stored.single.dedupeKey, '$packageId:quota20:2026-11-17');
  });

  test('dedupe key duplikat ditolak oleh UNIQUE constraint', () async {
    final first = await alerts.createIfAbsent(
      log(type: AlertType.daily100, at: today),
    );
    final second = await alerts.createIfAbsent(
      log(type: AlertType.daily100, at: today, message: 'Duplikat'),
    );

    expect(first, isNotNull);
    expect(second, isNull);
    expect(await alerts.getByPackage(packageId), hasLength(1));
  });

  test('alert hari berikutnya tetap tersimpan', () async {
    await alerts.createIfAbsent(log(type: AlertType.daily100, at: today));
    await alerts.createIfAbsent(
      log(type: AlertType.daily100, at: today.add(const Duration(days: 1))),
    );

    final stored = await alerts.getByPackage(packageId);

    expect(stored, hasLength(2));
    expect(stored.first.triggeredAt.isAfter(stored.last.triggeredAt), isTrue);
  });

  test('markRead mengubah status di SQLite', () async {
    final id = await alerts.createIfAbsent(
      log(type: AlertType.expiring1d, at: today),
    );

    await alerts.markRead(id!);

    final stored = await alerts.getByPackage(packageId);
    expect(stored.single.isRead, isTrue);

    final rows = await (await helper.database).query(
      'alert_logs',
      columns: ['is_read'],
      where: 'id = ?',
      whereArgs: [id],
    );

    expect(rows.single['is_read'], 1);
  });

  test('markAllRead menandai seluruh alert satu paket', () async {
    await alerts.createIfAbsent(log(type: AlertType.daily80, at: today));
    await alerts.createIfAbsent(log(type: AlertType.dailyOver, at: today));

    await alerts.markAllRead(packageId);

    final stored = await alerts.getByPackage(packageId);
    expect(stored.every((alert) => alert.isRead), isTrue);
  });

  test('delete menghapus alert agar bisa dicoba ulang', () async {
    final id = await alerts.createIfAbsent(
      log(type: AlertType.dailyOver, at: today),
    );

    await alerts.delete(id!);

    expect(await alerts.getByPackage(packageId), isEmpty);
    expect(
      await alerts.existsByDedupeKey('$packageId:dailyOver:2026-11-17'),
      isFalse,
    );
  });
}
