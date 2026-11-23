// Regresi migrasi: database v1 nyata (dengan index dan seluruh tabel
// scaffold) serta database v3 yang header versinya tertinggal.
import 'package:datawise/core/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _createRealV1(DatabaseExecutor db) async {
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
  await db.execute(
    'CREATE INDEX idx_data_packages_user_active '
    'ON data_packages(user_id, is_active)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX idx_one_active_package_per_user '
    'ON data_packages(user_id) WHERE is_active = 1',
  );
  await db.execute('''
    CREATE TABLE quota_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      category_type TEXT NOT NULL,
      quota_bytes INTEGER NOT NULL,
      start_minute INTEGER,
      end_minute INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE (package_id, name)
    )
  ''');
  await db.execute(
    'CREATE UNIQUE INDEX idx_one_main_category_per_package '
    "ON quota_categories(package_id) WHERE category_type = 'main'",
  );
  await db.execute(
    'CREATE INDEX idx_quota_categories_package '
    'ON quota_categories(package_id)',
  );
  await db.execute('''
    CREATE TABLE usage_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL,
      record_date TEXT NOT NULL,
      used_bytes INTEGER NOT NULL,
      source TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE (package_id, record_date, source)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_usage_records_package_date '
    'ON usage_records(package_id, record_date)',
  );
  await db.execute('''
    CREATE TABLE classification_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL,
      category_id INTEGER NOT NULL,
      app_package_name TEXT NOT NULL,
      start_minute INTEGER,
      end_minute INTEGER,
      priority INTEGER NOT NULL DEFAULT 100,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_classification_rules_package_priority '
    'ON classification_rules(package_id, is_enabled, priority, id)',
  );
  await db.execute('''
    CREATE TABLE usage_allocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usage_record_id INTEGER NOT NULL,
      category_id INTEGER NOT NULL,
      app_package_name TEXT NOT NULL DEFAULT '',
      used_bytes INTEGER NOT NULL,
      UNIQUE (usage_record_id, category_id, app_package_name)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_usage_allocations_record '
    'ON usage_allocations(usage_record_id)',
  );
  await db.execute(
    'CREATE INDEX idx_usage_allocations_category '
    'ON usage_allocations(category_id)',
  );
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
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL,
      alert_type TEXT NOT NULL,
      alert_date TEXT NOT NULL,
      sent_at INTEGER NOT NULL,
      UNIQUE (package_id, alert_type, alert_date)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_alert_logs_package_date '
    'ON alert_logs(package_id, alert_date)',
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'v1 nyata (dengan index) dapat dimigrasikan tanpa kehilangan data',
    () async {
      const path = 'tmp_audit_v1_real.db';
      await databaseFactory.deleteDatabase(path);

      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, v) async {
            await _createRealV1(db);
            await db.insert('data_packages', {
              'id': 7,
              'user_id': 'u1',
              'name': 'Legacy',
              'operator': 'Telkomsel',
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
          },
        ),
      );
      await old.close();

      final migrated = DbHelper.forTesting(path);
      try {
        final db = await migrated.database;
        final packages = await db.query('data_packages');
        expect(packages, hasLength(1));
        expect(packages.single['package_name'], 'Legacy');
        final usage = await db.query('usage_records');
        expect(usage.single['id'], 'legacy_usage_9');
        final version = await db.rawQuery('PRAGMA user_version');
        expect(version.single.values.first, 3);
      } finally {
        await migrated.close();
        await databaseFactory.deleteDatabase(path);
      }
    },
  );

  test('header version tertinggal pada skema v3 dipulihkan', () async {
    const path = 'tmp_audit_v3_stale.db';
    await databaseFactory.deleteDatabase(path);

    final helper = DbHelper.forTesting(path);
    final db = await helper.database;
    await db.insert('users', {
      'id': 'u1',
      'created_at': '2026-11-01T00:00:00.000Z',
      'updated_at': '2026-11-01T00:00:00.000Z',
    });
    await db.insert('data_packages', {
      'id': 'p1',
      'user_id': 'u1',
      'package_name': 'Tetap Ada',
      'advertised_total_quota_bytes': 1000,
      'start_date': '2026-11-01',
      'end_date': '2026-12-01',
      'status': 'ACTIVE',
      'created_at': '2026-11-01T00:00:00.000Z',
      'updated_at': '2026-11-01T00:00:00.000Z',
    });
    await db.execute('PRAGMA user_version = 1');
    await helper.close();

    final reopened = DbHelper.forTesting(path);
    try {
      final db2 = await reopened.database;
      final packages = await db2.query('data_packages');
      expect(packages, hasLength(1));
      expect(packages.single['package_name'], 'Tetap Ada');
      final version = await db2.rawQuery('PRAGMA user_version');
      expect(version.single.values.first, 3);
      final archive = await db2.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'legacy_data_packages'",
      );
      expect(archive, isEmpty);
    } finally {
      await reopened.close();
      await databaseFactory.deleteDatabase(path);
    }
  });
}
