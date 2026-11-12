// Satu-satunya pemilik skema SQLite. Semua perubahan skema wajib lewat migrasi.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'constants.dart';

class DbHelper {
  DbHelper._({String? databasePath}) : _databasePath = databasePath;

  static final DbHelper instance = DbHelper._();

  /// Membuat helper dengan lokasi khusus untuk pengujian.
  factory DbHelper.forTesting(String databasePath) =>
      DbHelper._(databasePath: databasePath);

  final String? _databasePath;
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final path = _databasePath ??
        p.join(await getDatabasesPath(), AppConstants.dbName);

    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }
      },
    );
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    for (final sql in _createStatements) {
      await db.execute(sql);
    }
    for (final sql in _triggerStatements) {
      await db.execute(sql);
    }
  }

  /// Database v1 adalah scaffold empat tabel. Data paket, pemakaian, dan
  /// alert yang dikenal dipindahkan. Preferensi lama dan alert tak dikenal
  /// diarsipkan karena pemilik/arti datanya tidak bisa dipastikan.
  static Future<void> _migrateV1ToV2(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE data_packages RENAME TO legacy_data_packages',
    );
    await db.execute(
      'ALTER TABLE usage_records RENAME TO legacy_usage_records',
    );
    await db.execute(
      'ALTER TABLE alert_logs RENAME TO legacy_alert_logs',
    );
    await db.execute(
      'ALTER TABLE app_settings RENAME TO legacy_app_settings',
    );

    await _createSchema(db);

    await db.execute('''
      INSERT INTO data_packages (
        id, user_id, name, operator, total_bytes, initial_used_bytes,
        start_date, end_date, price, is_active, created_at, updated_at
      )
      SELECT
        id, user_id, name, operator, total_bytes, initial_used_bytes,
        start_date, end_date, price,
        CASE
          WHEN is_active = 1 AND id = (
            SELECT MAX(candidate.id)
            FROM legacy_data_packages AS candidate
            WHERE candidate.user_id = legacy_data_packages.user_id
              AND candidate.is_active = 1
          ) THEN 1
          ELSE 0
        END,
        created_at, updated_at
      FROM legacy_data_packages
    ''');

    // Setiap paket lama harus tetap memiliki kategori utama setelah migrasi.
    // Karena scaffold lama belum mengenal kategori, seluruh kuota awal
    // ditempatkan pada kategori utama.
    await db.execute('''
      INSERT INTO quota_categories (
        package_id, name, category_type, quota_bytes, created_at, updated_at
      )
      SELECT
        id, 'Kuota Utama', 'main', total_bytes, created_at, updated_at
      FROM data_packages
    ''');

    await db.execute('''
      INSERT INTO usage_records (
        id, package_id, record_date, used_bytes, source, updated_at
      )
      SELECT id, package_id, record_date, used_bytes, source, updated_at
      FROM legacy_usage_records
    ''');

    await db.execute('''
      INSERT INTO alert_logs (
        id, package_id, alert_type, alert_date, sent_at
      )
      SELECT id, package_id, alert_type, alert_date, sent_at
      FROM legacy_alert_logs
      WHERE alert_type IN (
        'daily80', 'daily100', 'dailyOver', 'quota10', 'expiring1d'
      )
    ''');

    await db.execute('''
      CREATE TABLE legacy_alert_logs_archive AS
      SELECT *
      FROM legacy_alert_logs
      WHERE alert_type NOT IN (
        'daily80', 'daily100', 'dailyOver', 'quota10', 'expiring1d'
      )
    ''');

    // Hapus tabel lama dari yang paling bergantung ke tabel induk.
    await db.execute('DROP TABLE legacy_usage_records');
    await db.execute('DROP TABLE legacy_alert_logs');
    await db.execute('DROP TABLE legacy_data_packages');

    // legacy_app_settings dan legacy_alert_logs_archive sengaja dipertahankan
    // sebagai arsip. Jangan hapus sebelum pemetaan datanya disepakati.
  }

  static const List<String> _createStatements = [
    '''
    CREATE TABLE data_packages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      operator TEXT NOT NULL,
      total_bytes INTEGER NOT NULL CHECK (total_bytes > 0),
      initial_used_bytes INTEGER NOT NULL DEFAULT 0
        CHECK (initial_used_bytes >= 0),
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      price INTEGER,
      is_active INTEGER NOT NULL DEFAULT 0
        CHECK (is_active IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      CHECK (end_date > start_date)
    )
    ''',
    '''
    CREATE INDEX idx_data_packages_user_active
    ON data_packages(user_id, is_active)
    ''',
    '''
    CREATE UNIQUE INDEX idx_one_active_package_per_user
    ON data_packages(user_id)
    WHERE is_active = 1
    ''',
    '''
    CREATE TABLE quota_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL
        REFERENCES data_packages(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      category_type TEXT NOT NULL
        CHECK (category_type IN ('main', 'night', 'social', 'app', 'custom')),
      quota_bytes INTEGER NOT NULL CHECK (quota_bytes > 0),
      start_minute INTEGER
        CHECK (start_minute IS NULL OR start_minute BETWEEN 0 AND 1439),
      end_minute INTEGER
        CHECK (end_minute IS NULL OR end_minute BETWEEN 0 AND 1439),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE (package_id, name)
    )
    ''',
    '''
    CREATE UNIQUE INDEX idx_one_main_category_per_package
    ON quota_categories(package_id)
    WHERE category_type = 'main'
    ''',
    '''
    CREATE INDEX idx_quota_categories_package
    ON quota_categories(package_id)
    ''',
    '''
    CREATE TABLE usage_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL
        REFERENCES data_packages(id) ON DELETE CASCADE,
      record_date TEXT NOT NULL,
      used_bytes INTEGER NOT NULL CHECK (used_bytes >= 0),
      source TEXT NOT NULL CHECK (source IN ('auto', 'manual')),
      updated_at INTEGER NOT NULL,
      UNIQUE (package_id, record_date, source)
    )
    ''',
    '''
    CREATE INDEX idx_usage_records_package_date
    ON usage_records(package_id, record_date)
    ''',
    '''
    CREATE TABLE classification_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL
        REFERENCES data_packages(id) ON DELETE CASCADE,
      category_id INTEGER NOT NULL
        REFERENCES quota_categories(id) ON DELETE CASCADE,
      app_package_name TEXT NOT NULL,
      start_minute INTEGER
        CHECK (start_minute IS NULL OR start_minute BETWEEN 0 AND 1439),
      end_minute INTEGER
        CHECK (end_minute IS NULL OR end_minute BETWEEN 0 AND 1439),
      priority INTEGER NOT NULL DEFAULT 100,
      is_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (is_enabled IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE INDEX idx_classification_rules_package_priority
    ON classification_rules(package_id, is_enabled, priority, id)
    ''',
    '''
    CREATE TABLE usage_allocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usage_record_id INTEGER NOT NULL
        REFERENCES usage_records(id) ON DELETE CASCADE,
      category_id INTEGER NOT NULL
        REFERENCES quota_categories(id) ON DELETE CASCADE,
      app_package_name TEXT NOT NULL DEFAULT '',
      used_bytes INTEGER NOT NULL CHECK (used_bytes >= 0),
      UNIQUE (usage_record_id, category_id, app_package_name)
    )
    ''',
    '''
    CREATE INDEX idx_usage_allocations_record
    ON usage_allocations(usage_record_id)
    ''',
    '''
    CREATE INDEX idx_usage_allocations_category
    ON usage_allocations(category_id)
    ''',
    '''
    CREATE TABLE data_limit_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL UNIQUE
        REFERENCES data_packages(id) ON DELETE CASCADE,
      daily_warning_percent INTEGER NOT NULL DEFAULT 100
        CHECK (daily_warning_percent > 0),
      quota_warning_percent INTEGER NOT NULL DEFAULT 10
        CHECK (quota_warning_percent BETWEEN 1 AND 100),
      is_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (is_enabled IN (0, 1)),
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE user_settings (
      user_id TEXT NOT NULL,
      key TEXT NOT NULL,
      value TEXT NOT NULL,
      PRIMARY KEY (user_id, key)
    )
    ''',
    '''
    CREATE TABLE alert_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_id INTEGER NOT NULL
        REFERENCES data_packages(id) ON DELETE CASCADE,
      alert_type TEXT NOT NULL
        CHECK (alert_type IN (
          'daily80', 'daily100', 'dailyOver', 'quota10', 'expiring1d'
        )),
      alert_date TEXT NOT NULL,
      sent_at INTEGER NOT NULL,
      UNIQUE (package_id, alert_type, alert_date)
    )
    ''',
    '''
    CREATE INDEX idx_alert_logs_package_date
    ON alert_logs(package_id, alert_date)
    ''',
  ];

  static const List<String> _triggerStatements = [
    '''
    CREATE TRIGGER validate_classification_rule_insert
    BEFORE INSERT ON classification_rules
    WHEN NOT EXISTS (
      SELECT 1 FROM quota_categories
      WHERE id = NEW.category_id AND package_id = NEW.package_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'classification category belongs to another package');
    END
    ''',
    '''
    CREATE TRIGGER validate_classification_rule_update
    BEFORE UPDATE OF package_id, category_id ON classification_rules
    WHEN NOT EXISTS (
      SELECT 1 FROM quota_categories
      WHERE id = NEW.category_id AND package_id = NEW.package_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'classification category belongs to another package');
    END
    ''',
    '''
    CREATE TRIGGER validate_usage_allocation_insert
    BEFORE INSERT ON usage_allocations
    WHEN NOT EXISTS (
      SELECT 1
      FROM usage_records AS usage
      JOIN quota_categories AS category
        ON category.id = NEW.category_id
      WHERE usage.id = NEW.usage_record_id
        AND usage.package_id = category.package_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'allocation category belongs to another package');
    END
    ''',
    '''
    CREATE TRIGGER validate_usage_allocation_update
    BEFORE UPDATE OF usage_record_id, category_id ON usage_allocations
    WHEN NOT EXISTS (
      SELECT 1
      FROM usage_records AS usage
      JOIN quota_categories AS category
        ON category.id = NEW.category_id
      WHERE usage.id = NEW.usage_record_id
        AND usage.package_id = category.package_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'allocation category belongs to another package');
    END
    ''',
    '''
    CREATE TRIGGER validate_allocation_total_insert
    BEFORE INSERT ON usage_allocations
    WHEN NEW.used_bytes + COALESCE((
      SELECT SUM(used_bytes) FROM usage_allocations
      WHERE usage_record_id = NEW.usage_record_id
    ), 0) > (
      SELECT used_bytes FROM usage_records WHERE id = NEW.usage_record_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'allocation total exceeds usage record');
    END
    ''',
    '''
    CREATE TRIGGER validate_allocation_total_update
    BEFORE UPDATE OF usage_record_id, used_bytes ON usage_allocations
    WHEN NEW.used_bytes + COALESCE((
      SELECT SUM(used_bytes) FROM usage_allocations
      WHERE usage_record_id = NEW.usage_record_id AND id != OLD.id
    ), 0) > (
      SELECT used_bytes FROM usage_records WHERE id = NEW.usage_record_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'allocation total exceeds usage record');
    END
    ''',
    '''
    CREATE TRIGGER validate_usage_record_update
    BEFORE UPDATE OF used_bytes ON usage_records
    WHEN COALESCE((
      SELECT SUM(used_bytes) FROM usage_allocations
      WHERE usage_record_id = OLD.id
    ), 0) > NEW.used_bytes
    BEGIN
      SELECT RAISE(ABORT, 'usage record is below its allocations');
    END
    ''',
    '''
    CREATE TRIGGER validate_category_total_insert
    BEFORE INSERT ON quota_categories
    WHEN COALESCE((
      SELECT SUM(quota_bytes) FROM quota_categories
      WHERE package_id = NEW.package_id
    ), 0) + NEW.quota_bytes > (
      SELECT total_bytes FROM data_packages WHERE id = NEW.package_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'category quotas exceed package quota');
    END
    ''',
    '''
    CREATE TRIGGER validate_category_total_update
    BEFORE UPDATE OF package_id, quota_bytes ON quota_categories
    WHEN COALESCE((
      SELECT SUM(quota_bytes) FROM quota_categories
      WHERE package_id = NEW.package_id AND id != OLD.id
    ), 0) + NEW.quota_bytes > (
      SELECT total_bytes FROM data_packages WHERE id = NEW.package_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'category quotas exceed package quota');
    END
    ''',
  ];
}
