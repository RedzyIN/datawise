import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datawise/core/db_helper.dart';

const _now = '2026-11-14T00:00:00.000Z';

Future<void> _insertUser(Database db, String id) async {
  await db.insert('users', {
    'id': id,
    'display_name': null,
    'email': null,
    'created_at': _now,
    'updated_at': _now,
  });
}

Future<String> _insertPackage(
  Database db, {
  required String id,
  required String userId,
  String status = 'ACTIVE',
  int quotaBytes = 1000,
}) async {
  await db.insert('data_packages', {
    'id': id,
    'user_id': userId,
    'package_name': 'Paket $id',
    'operator_name': 'Test',
    'advertised_total_quota_bytes': quotaBytes,
    'start_date': '2026-11-01',
    'end_date': '2026-12-01',
    'status': status,
    'created_at': _now,
    'updated_at': _now,
  });

  return id;
}

Future<String> _insertCategory(
  Database db, {
  required String id,
  required String packageId,
  String categoryType = 'MAIN',
  int capacityBytes = 1000,
}) async {
  await db.insert('quota_categories', {
    'id': id,
    'package_id': packageId,
    'category_name': 'Kategori $id',
    'category_type': categoryType,
    'capacity_bytes': capacityBytes,
    'valid_from': null,
    'valid_until': null,
    'is_enabled': 1,
    'created_at': _now,
  });

  return id;
}

Future<String> _insertUsage(
  Database db, {
  required String id,
  required String packageId,
  int rxBytes = 100,
  int txBytes = 0,
}) async {
  await db.insert('usage_records', {
    'id': id,
    'package_id': packageId,
    'record_scope': 'APP_USAGE',
    'app_uid': 10001,
    'app_package_name': 'com.example.app',
    'app_name': 'Example App',
    'network_type': 'MOBILE',
    'period_start_at': '2026-11-14T00:00:00.000Z',
    'period_end_at': '2026-11-14T23:59:59.999Z',
    'rx_bytes': rxBytes,
    'tx_bytes': txBytes,
    'source': 'ANDROID',
    'source_key': 'source_$id',
    'recorded_at': _now,
  });

  return id;
}

void main() {
  late DbHelper helper;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    const path = 'datawise_schema_test.db';
    await databaseFactory.deleteDatabase(path);
    helper = DbHelper.forTesting(path);
  });

  tearDown(() async {
    await helper.close();
  });

  test('v3 creates required tables and enables foreign keys', () async {
    final db = await helper.database;

    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    final names = rows.map((row) => row['name'] as String).toSet();

    expect(
      names,
      containsAll({
        'users',
        'data_packages',
        'quota_categories',
        'usage_records',
        'classification_rules',
        'usage_allocations',
        'data_limit_settings',
        'user_settings',
        'alert_logs',
      }),
    );

    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.first.values.first, 1);
  });

  test('only one active package is allowed per user', () async {
    final db = await helper.database;

    await _insertUser(db, 'u1');

    await _insertPackage(db, id: 'p1', userId: 'u1');

    await expectLater(
      _insertPackage(db, id: 'p2', userId: 'u1'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('category capacity cannot exceed package quota', () async {
    final db = await helper.database;

    await _insertUser(db, 'u1');

    await _insertPackage(db, id: 'p1', userId: 'u1', quotaBytes: 1000);

    await _insertCategory(db, id: 'c1', packageId: 'p1', capacityBytes: 700);

    await expectLater(
      _insertCategory(
        db,
        id: 'c2',
        packageId: 'p1',
        categoryType: 'CUSTOM',
        capacityBytes: 400,
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('allocation cannot reference another package category', () async {
    final db = await helper.database;

    await _insertUser(db, 'u1');
    await _insertUser(db, 'u2');

    await _insertPackage(db, id: 'p1', userId: 'u1');

    await _insertPackage(db, id: 'p2', userId: 'u2');

    await _insertCategory(db, id: 'c1', packageId: 'p1');

    await _insertUsage(db, id: 'usage1', packageId: 'p2');

    await expectLater(
      db.insert('usage_allocations', {
        'id': 'allocation1',
        'package_id': 'p2',
        'usage_record_id': 'usage1',
        'quota_category_id': 'c1',
        'classification_rule_id': null,
        'allocated_bytes': 50,
        'allocation_method': 'MAIN_FALLBACK',
        'created_at': _now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('allocation total cannot exceed usage record', () async {
    final db = await helper.database;

    await _insertUser(db, 'u1');

    await _insertPackage(db, id: 'p1', userId: 'u1');

    await _insertCategory(db, id: 'c1', packageId: 'p1');

    await _insertUsage(db, id: 'usage1', packageId: 'p1', rxBytes: 100);

    await db.insert('usage_allocations', {
      'id': 'allocation1',
      'package_id': 'p1',
      'usage_record_id': 'usage1',
      'quota_category_id': 'c1',
      'classification_rule_id': null,
      'allocated_bytes': 60,
      'allocation_method': 'MAIN_FALLBACK',
      'created_at': _now,
    });

    await expectLater(
      db.insert('usage_allocations', {
        'id': 'allocation2',
        'package_id': 'p1',
        'usage_record_id': 'usage1',
        'quota_category_id': 'c1',
        'classification_rule_id': null,
        'allocated_bytes': 50,
        'allocation_method': 'MAIN_FALLBACK',
        'created_at': _now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('v1 migrates to v3 and preserves supported data', () async {
    const path = 'datawise_migration_v1_test.db';

    await databaseFactory.deleteDatabase(path);

    final oldDb = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE data_packages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL,
              name TEXT NOT NULL,
              operator TEXT NOT NULL,
              total_bytes INTEGER NOT NULL,
              initial_used_bytes INTEGER NOT NULL DEFAULT 0,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              price INTEGER,
              is_active INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE usage_records (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              package_id INTEGER NOT NULL,
              record_date TEXT NOT NULL,
              used_bytes INTEGER NOT NULL,
              source TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              UNIQUE(package_id, record_date, source)
            )
          ''');

          await db.execute('''
            CREATE TABLE alert_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              package_id INTEGER NOT NULL,
              alert_type TEXT NOT NULL,
              alert_date TEXT NOT NULL,
              sent_at INTEGER NOT NULL,
              UNIQUE(package_id, alert_type, alert_date)
            )
          ''');

          await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');

          await db.insert('data_packages', {
            'id': 7,
            'user_id': 'u1',
            'name': 'Legacy',
            'operator': 'Test',
            'total_bytes': 20000000000,
            'initial_used_bytes': 0,
            'start_date': '2026-11-01',
            'end_date': '2026-12-01',
            'is_active': 1,
            'created_at': 100,
            'updated_at': 100,
          });

          await db.insert('usage_records', {
            'id': 9,
            'package_id': 7,
            'record_date': '2026-11-12',
            'used_bytes': 123,
            'source': 'auto',
            'updated_at': 200,
          });

          await db.insert('alert_logs', {
            'id': 3,
            'package_id': 7,
            'alert_type': 'daily80',
            'alert_date': '2026-11-12',
            'sent_at': 300,
          });

          await db.insert('app_settings', {'key': 'theme', 'value': 'dark'});
        },
      ),
    );

    await oldDb.close();

    final migrated = DbHelper.forTesting(path);

    try {
      final db = await migrated.database;

      final package = (await db.query('data_packages')).single;
      expect(package['id'], 'legacy_package_7');
      expect(package['user_id'], 'u1');
      expect(package['package_name'], 'Legacy');
      expect(package['status'], 'ACTIVE');

      final usage = (await db.query('usage_records')).single;
      expect(usage['id'], 'legacy_usage_9');
      expect(usage['package_id'], 'legacy_package_7');
      expect(usage['record_scope'], 'DEVICE_TOTAL');
      expect(usage['rx_bytes'], 123);
      expect(usage['tx_bytes'], 0);

      final category = (await db.query('quota_categories')).single;
      expect(category['category_type'], 'MAIN');
      expect(category['capacity_bytes'], 20000000000);

      final alert = (await db.query('alert_logs')).single;
      expect(alert['id'], 'legacy_alert_3');
      expect(alert['alert_type'], 'daily80');

      expect(await db.query('users'), hasLength(1));
      expect(await db.query('legacy_app_settings'), hasLength(1));

      final foreignKeyErrors = await db.rawQuery('PRAGMA foreign_key_check');
      expect(foreignKeyErrors, isEmpty);
    } finally {
      await migrated.close();
      await databaseFactory.deleteDatabase(path);
    }
  });

  test('v2 migrates to v3 and preserves data and legacy archives', () async {
    const path = 'datawise_migration_v2_test.db';

    await databaseFactory.deleteDatabase(path);

    final oldDb = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE data_packages (
              id INTEGER PRIMARY KEY,
              user_id TEXT NOT NULL,
              name TEXT NOT NULL,
              operator TEXT NOT NULL,
              total_bytes INTEGER NOT NULL,
              initial_used_bytes INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              price INTEGER,
              is_active INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE quota_categories (
              id INTEGER PRIMARY KEY,
              package_id INTEGER NOT NULL REFERENCES data_packages(id),
              name TEXT NOT NULL,
              category_type TEXT NOT NULL,
              quota_bytes INTEGER NOT NULL,
              start_minute INTEGER,
              end_minute INTEGER,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE usage_records (
              id INTEGER PRIMARY KEY,
              package_id INTEGER NOT NULL REFERENCES data_packages(id),
              record_date TEXT NOT NULL,
              used_bytes INTEGER NOT NULL,
              source TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE classification_rules (
              id INTEGER PRIMARY KEY,
              package_id INTEGER NOT NULL REFERENCES data_packages(id),
              category_id INTEGER NOT NULL REFERENCES quota_categories(id),
              app_package_name TEXT NOT NULL,
              start_minute INTEGER,
              end_minute INTEGER,
              priority INTEGER NOT NULL,
              is_enabled INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE usage_allocations (
              id INTEGER PRIMARY KEY,
              usage_record_id INTEGER NOT NULL REFERENCES usage_records(id),
              category_id INTEGER NOT NULL REFERENCES quota_categories(id),
              app_package_name TEXT NOT NULL,
              used_bytes INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE data_limit_settings (
              id INTEGER PRIMARY KEY,
              package_id INTEGER NOT NULL UNIQUE REFERENCES data_packages(id),
              daily_warning_percent INTEGER NOT NULL,
              quota_warning_percent INTEGER NOT NULL,
              is_enabled INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE user_settings (
              user_id TEXT NOT NULL,
              key TEXT NOT NULL,
              value TEXT NOT NULL,
              PRIMARY KEY (user_id, key)
            )
          ''');

          await db.execute('''
            CREATE TABLE alert_logs (
              id INTEGER PRIMARY KEY,
              package_id INTEGER NOT NULL REFERENCES data_packages(id),
              alert_type TEXT NOT NULL,
              alert_date TEXT NOT NULL,
              sent_at INTEGER NOT NULL
            )
          ''');

          await db.insert('data_packages', {
            'id': 7,
            'user_id': 'u1',
            'name': 'Paket V2',
            'operator': 'Test',
            'total_bytes': 20000000000,
            'initial_used_bytes': 500,
            'start_date': '2026-11-01',
            'end_date': '2026-12-01',
            'price': 50000,
            'is_active': 1,
            'created_at': 100000,
            'updated_at': 200000,
          });

          await db.insert('quota_categories', {
            'id': 11,
            'package_id': 7,
            'name': 'Kuota Utama',
            'category_type': 'main',
            'quota_bytes': 20000000000,
            'created_at': 100000,
            'updated_at': 100000,
          });

          await db.insert('usage_records', {
            'id': 9,
            'package_id': 7,
            'record_date': '2026-11-12',
            'used_bytes': 123,
            'source': 'auto',
            'updated_at': 200000,
          });

          await db.insert('usage_records', {
            'id': 10,
            'package_id': 7,
            'record_date': '2026-11-11',
            'used_bytes': 250,
            'source': 'manual',
            'updated_at': 150000,
          });

          await db.insert('classification_rules', {
            'id': 4,
            'package_id': 7,
            'category_id': 11,
            'app_package_name': 'com.example.app',
            'priority': 100,
            'is_enabled': 1,
            'created_at': 100000,
            'updated_at': 100000,
          });

          await db.insert('usage_allocations', {
            'id': 15,
            'usage_record_id': 9,
            'category_id': 11,
            'app_package_name': 'com.example.app',
            'used_bytes': 50,
          });

          await db.insert('data_limit_settings', {
            'id': 2,
            'package_id': 7,
            'daily_warning_percent': 80,
            'quota_warning_percent': 10,
            'is_enabled': 1,
            'updated_at': 200000,
          });

          await db.insert('user_settings', {
            'user_id': 'u1',
            'key': 'theme_mode',
            'value': 'DARK',
          });

          await db.insert('user_settings', {
            'user_id': 'u1',
            'key': 'notif_enabled',
            'value': '0',
          });

          await db.insert('alert_logs', {
            'id': 3,
            'package_id': 7,
            'alert_type': 'daily80',
            'alert_date': '2026-11-12',
            'sent_at': 300000,
          });
        },
      ),
    );

    await oldDb.close();

    final migrated = DbHelper.forTesting(path);

    try {
      final db = await migrated.database;

      final package = (await db.query('data_packages')).single;
      expect(package['id'], 'legacy_package_7');
      expect(package['package_name'], 'Paket V2');
      expect(package['status'], 'ACTIVE');

      final category = (await db.query('quota_categories')).single;
      expect(category['id'], 'legacy_category_11');
      expect(category['category_type'], 'MAIN');

      final usageRows = await db.query(
        'usage_records',
        where: 'id = ?',
        whereArgs: ['legacy_usage_9'],
      );
      final usage = usageRows.single;
      expect(usage['record_scope'], 'DEVICE_TOTAL');
      expect(usage['rx_bytes'], 123);

      final manualUsageRows = await db.query(
        'usage_records',
        where: 'id = ?',
        whereArgs: ['legacy_usage_10'],
      );
      expect(manualUsageRows.single['record_scope'], 'MANUAL_TOTAL');
      final migratedManualAllocations = await db.query(
        'usage_allocations',
        where: 'usage_record_id = ?',
        whereArgs: ['legacy_usage_10'],
      );
      expect(migratedManualAllocations, hasLength(1));
      expect(migratedManualAllocations.single['allocated_bytes'], 250);
      expect(
        migratedManualAllocations.single['allocation_method'],
        'UNCLASSIFIED',
      );

      final rule = (await db.query('classification_rules')).single;
      expect(rule['id'], 'legacy_rule_4');
      expect(rule['quota_category_id'], 'legacy_category_11');
      expect(rule['app_package_name'], 'com.example.app');

      final settings = (await db.query('user_settings')).single;
      expect(settings['theme_mode'], 'DARK');
      expect(settings['notifications_enabled'], 0);

      final alert = (await db.query('alert_logs')).single;
      expect(alert['id'], 'legacy_alert_3');
      expect(alert['alert_type'], 'daily80');

      // Alokasi lama tetap tersedia di arsip.
      // Data otomatis lama menjadi DEVICE_TOTAL, sehingga tidak boleh
      // dipindahkan sebagai alokasi aktif pada skema v3.
      final archivedAllocation = await db.query('legacy_v2_usage_allocations');
      expect(archivedAllocation, hasLength(1));
      expect(archivedAllocation.single['used_bytes'], 50);

      expect(await db.query('usage_allocations'), hasLength(1));
      expect(
        (await db.query('usage_allocations')).single['id'],
        'legacy_manual_allocation_10',
      );

      // Kolom yang tidak memiliki padanan di v3 tetap tersedia di arsip.
      final archivedPackage = (await db.query('legacy_v2_data_packages'))
          .single;
      expect(archivedPackage['initial_used_bytes'], 500);
      expect(archivedPackage['price'], 50000);

      final archivedLimit = (await db.query('legacy_v2_data_limit_settings'))
          .single;
      expect(archivedLimit['daily_warning_percent'], 80);

      final foreignKeyErrors = await db.rawQuery('PRAGMA foreign_key_check');
      expect(foreignKeyErrors, isEmpty);
    } finally {
      await migrated.close();
      await databaseFactory.deleteDatabase(path);
    }
  });
}
