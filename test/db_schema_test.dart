import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datawise/core/db_helper.dart';

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

  test('database creates eight tables and enables foreign keys', () async {
    final db = await helper.database;
    final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final names = rows.map((row) => row['name'] as String).toSet();
    expect(names, containsAll({
      'data_packages', 'quota_categories', 'usage_records',
      'classification_rules', 'usage_allocations',
      'data_limit_settings', 'user_settings', 'alert_logs',
    }));
    expect((await db.rawQuery('PRAGMA foreign_keys')).first.values.first, 1);
  });

  test('partial unique index prevents two active packages per user', () async {
    final db = await helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    Future<void> add(String name) async {
      await db.insert('data_packages', {
        'user_id': 'u1', 'name': name, 'operator': 'Test',
        'total_bytes': 1000, 'initial_used_bytes': 0,
        'start_date': '2026-11-01', 'end_date': '2026-12-01',
        'is_active': 1, 'created_at': now, 'updated_at': now,
      });
    }
    await add('Paket A');
    await expectLater(add('Paket B'), throwsA(isA<DatabaseException>()));
  });

  test('trigger rejects a category belonging to another package', () async {
    final db = await helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    Future<int> addPackage(String uid) => db.insert('data_packages', {
      'user_id': uid, 'name': 'Paket', 'operator': 'Test',
      'total_bytes': 1000, 'initial_used_bytes': 0,
      'start_date': '2026-11-01', 'end_date': '2026-12-01',
      'created_at': now, 'updated_at': now,
    });
    final p1 = await addPackage('u1');
    final p2 = await addPackage('u2');
    final c1 = await db.insert('quota_categories', {
      'package_id': p1, 'name': 'Main', 'category_type': 'main',
      'quota_bytes': 1000, 'created_at': now, 'updated_at': now,
    });
    final usage = await db.insert('usage_records', {
      'package_id': p2, 'record_date': '2026-11-12',
      'used_bytes': 100, 'source': 'auto', 'updated_at': now,
    });
    await expectLater(
      db.insert('usage_allocations', {
        'usage_record_id': usage, 'category_id': c1,
        'app_package_name': 'com.example.app', 'used_bytes': 50,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('trigger rejects allocation sum greater than usage', () async {
    final db = await helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = await db.insert('data_packages', {
      'user_id': 'u1', 'name': 'Paket', 'operator': 'Test',
      'total_bytes': 1000, 'initial_used_bytes': 0,
      'start_date': '2026-11-01', 'end_date': '2026-12-01',
      'created_at': now, 'updated_at': now,
    });
    final c = await db.insert('quota_categories', {
      'package_id': p, 'name': 'Main', 'category_type': 'main',
      'quota_bytes': 1000, 'created_at': now, 'updated_at': now,
    });
    final u = await db.insert('usage_records', {
      'package_id': p, 'record_date': '2026-11-12',
      'used_bytes': 100, 'source': 'auto', 'updated_at': now,
    });
    await db.insert('usage_allocations', {
      'usage_record_id': u, 'category_id': c,
      'app_package_name': 'com.example.one', 'used_bytes': 60,
    });
    await expectLater(
      db.insert('usage_allocations', {
        'usage_record_id': u, 'category_id': c,
        'app_package_name': 'com.example.two', 'used_bytes': 50,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('v1 migration preserves packages and usage and creates main category', () async {
    const path = 'datawise_migration_test.db';
    await databaseFactory.deleteDatabase(path);
    final oldDb = await databaseFactory.openDatabase(path, options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE data_packages (
          id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,
          name TEXT NOT NULL, operator TEXT NOT NULL, total_bytes INTEGER NOT NULL,
          initial_used_bytes INTEGER NOT NULL DEFAULT 0, start_date TEXT NOT NULL,
          end_date TEXT NOT NULL, price INTEGER, is_active INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE usage_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT, package_id INTEGER NOT NULL,
          record_date TEXT NOT NULL, used_bytes INTEGER NOT NULL,
          source TEXT NOT NULL, updated_at INTEGER NOT NULL,
          UNIQUE(package_id, record_date, source))''');
        await db.execute('''CREATE TABLE alert_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT, package_id INTEGER NOT NULL,
          alert_type TEXT NOT NULL, alert_date TEXT NOT NULL, sent_at INTEGER NOT NULL,
          UNIQUE(package_id, alert_type, alert_date))''');
        await db.execute('CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.insert('data_packages', {
          'id': 7, 'user_id': 'u1', 'name': 'Legacy', 'operator': 'Test',
          'total_bytes': 20000000000, 'initial_used_bytes': 0,
          'start_date': '2026-11-01', 'end_date': '2026-12-01',
          'is_active': 1, 'created_at': 100, 'updated_at': 100,
        });
        await db.insert('usage_records', {
          'id': 9, 'package_id': 7, 'record_date': '2026-11-12',
          'used_bytes': 123, 'source': 'auto', 'updated_at': 200,
        });
        await db.insert('alert_logs', {
          'id': 3, 'package_id': 7, 'alert_type': 'daily80',
          'alert_date': '2026-11-12', 'sent_at': 300,
        });
        await db.insert('app_settings', {'key': 'theme', 'value': 'dark'});
      },
    ));
    await oldDb.close();

    final migrated = DbHelper.forTesting(path);
    final db = await migrated.database;
    expect((await db.query('data_packages')).single['id'], 7);
    expect((await db.query('usage_records')).single['used_bytes'], 123);
    expect((await db.query('quota_categories')).single['category_type'], 'main');
    expect((await db.query('alert_logs')).single['alert_type'], 'daily80');
    expect(await db.query('legacy_app_settings'), isNotEmpty);
    await migrated.close();
    await databaseFactory.deleteDatabase(path);
  });
}
