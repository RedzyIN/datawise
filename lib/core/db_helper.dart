// Satu-satunya pemilik skema SQLite. Semua perubahan skema wajib lewat migrasi.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'constants.dart';

class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final sql in _createStatements) {
          await db.execute(sql);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Simpan data dari skema scaffold lama sebelum membuat tabel v2.
          await db.execute('ALTER TABLE data_packages RENAME TO legacy_data_packages');
          await db.execute('ALTER TABLE usage_records RENAME TO legacy_usage_records');
          await db.execute('ALTER TABLE alert_logs RENAME TO legacy_alert_logs');
          for (final sql in _createStatements) {
            await db.execute(sql);
          }
          await db.execute('''INSERT INTO data_packages
            (id,user_id,name,operator,total_bytes,initial_used_bytes,start_date,end_date,price,is_active,created_at,updated_at)
            SELECT id,user_id,name,operator,total_bytes,initial_used_bytes,start_date,end_date,price,is_active,created_at,updated_at
            FROM legacy_data_packages''');
          await db.execute('''INSERT INTO usage_records
            (id,package_id,record_date,used_bytes,source,updated_at)
            SELECT id,package_id,record_date,used_bytes,source,updated_at
            FROM legacy_usage_records''');
          await db.execute('''INSERT INTO alert_logs
            (id,package_id,alert_type,alert_date,sent_at)
            SELECT id,package_id,alert_type,alert_date,sent_at
            FROM legacy_alert_logs''');
          await db.execute('DROP TABLE legacy_usage_records');
          await db.execute('DROP TABLE legacy_alert_logs');
          await db.execute('DROP TABLE legacy_data_packages');
          // app_settings lama dipertahankan sebagai arsip. Nilainya tidak
          // dipindahkan karena tidak memiliki Firebase UID pemilik.
        }
      },
    );
  }

  static const List<String> _createStatements = [
    '''CREATE TABLE data_packages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL, name TEXT NOT NULL, operator TEXT NOT NULL,
      total_bytes INTEGER NOT NULL CHECK(total_bytes > 0),
      initial_used_bytes INTEGER NOT NULL DEFAULT 0 CHECK(initial_used_bytes >= 0),
      start_date TEXT NOT NULL, end_date TEXT NOT NULL, price INTEGER,
      is_active INTEGER NOT NULL DEFAULT 0 CHECK(is_active IN (0,1)),
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      CHECK(end_date > start_date)
    )''',
    'CREATE INDEX idx_data_packages_user_active ON data_packages(user_id, is_active)',
    'CREATE UNIQUE INDEX idx_one_active_package_per_user ON data_packages(user_id) WHERE is_active = 1',
    '''CREATE TABLE quota_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      category_type TEXT NOT NULL CHECK(category_type IN ('main','night','social','app','custom')),
      quota_bytes INTEGER NOT NULL CHECK(quota_bytes > 0),
      start_minute INTEGER CHECK(start_minute IS NULL OR start_minute BETWEEN 0 AND 1439),
      end_minute INTEGER CHECK(end_minute IS NULL OR end_minute BETWEEN 0 AND 1439),
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      UNIQUE(package_id, name)
    )''',
    'CREATE UNIQUE INDEX idx_one_main_category_per_package ON quota_categories(package_id) WHERE category_type = \'main\'',
    'CREATE INDEX idx_quota_categories_package ON quota_categories(package_id)',
    '''CREATE TABLE usage_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
      record_date TEXT NOT NULL, used_bytes INTEGER NOT NULL CHECK(used_bytes >= 0),
      source TEXT NOT NULL CHECK(source IN ('auto','manual')),
      updated_at INTEGER NOT NULL, UNIQUE(package_id, record_date, source)
    )''',
    'CREATE INDEX idx_usage_records_package_date ON usage_records(package_id, record_date)',
    '''CREATE TABLE classification_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
      category_id INTEGER NOT NULL REFERENCES quota_categories(id) ON DELETE CASCADE,
      app_package_name TEXT NOT NULL,
      start_minute INTEGER CHECK(start_minute IS NULL OR start_minute BETWEEN 0 AND 1439),
      end_minute INTEGER CHECK(end_minute IS NULL OR end_minute BETWEEN 0 AND 1439),
      priority INTEGER NOT NULL DEFAULT 100,
      is_enabled INTEGER NOT NULL DEFAULT 1 CHECK(is_enabled IN (0,1)),
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_classification_rules_package_priority ON classification_rules(package_id, is_enabled, priority, id)',
    '''CREATE TABLE usage_allocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usage_record_id INTEGER NOT NULL REFERENCES usage_records(id) ON DELETE CASCADE,
      category_id INTEGER NOT NULL REFERENCES quota_categories(id) ON DELETE CASCADE,
      app_package_name TEXT NOT NULL DEFAULT '',
      used_bytes INTEGER NOT NULL CHECK(used_bytes >= 0),
      UNIQUE(usage_record_id, category_id, app_package_name)
    )''',
    'CREATE INDEX idx_usage_allocations_record ON usage_allocations(usage_record_id)',
    'CREATE INDEX idx_usage_allocations_category ON usage_allocations(category_id)',
    '''CREATE TABLE data_limit_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL UNIQUE REFERENCES data_packages(id) ON DELETE CASCADE,
      daily_warning_percent INTEGER NOT NULL DEFAULT 100 CHECK(daily_warning_percent > 0),
      quota_warning_percent INTEGER NOT NULL DEFAULT 10 CHECK(quota_warning_percent BETWEEN 1 AND 100),
      is_enabled INTEGER NOT NULL DEFAULT 1 CHECK(is_enabled IN (0,1)),
      updated_at INTEGER NOT NULL
    )''',
    '''CREATE TABLE user_settings (
      user_id TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL,
      PRIMARY KEY(user_id, key)
    )''',
    '''CREATE TABLE alert_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
      alert_type TEXT NOT NULL CHECK(alert_type IN ('daily80','daily100','dailyOver','quota10','expiring1d')),
      alert_date TEXT NOT NULL, sent_at INTEGER NOT NULL,
      UNIQUE(package_id, alert_type, alert_date)
    )''',
    'CREATE INDEX idx_alert_logs_package_date ON alert_logs(package_id, alert_date)',
  ];
}
