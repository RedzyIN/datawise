// Satu-satunya pemilik skema SQLite. Semua perubahan skema wajib lewat migrasi.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'constants.dart';

class DbHelper {
  DbHelper._({this._databasePath});

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
    final path =
        _databasePath ?? p.join(await getDatabasesPath(), AppConstants.dbName);

    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV3Schema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Sebagian build lama sudah menulis skema v3 tanpa memperbarui
        // PRAGMA user_version. Menjalankan migrasi v1/v2 pada database seperti
        // itu akan gagal (tabel lama tidak ada) sehingga database tidak pernah
        // bisa dibuka dan semua query ikut gagal. Deteksi skema lebih dulu,
        // lalu cukup tandai versinya. sqflite menulis versi setelah callback
        // onUpgrade selesai, jadi data pengguna tidak disentuh.
        if (await _hasV3Schema(db)) return;

        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }

        if (oldVersion < 3) {
          await _migrateV2ToV3(db);
        }
      },
    );
  }

  /// Apakah database sudah memakai skema v3?
  ///
  /// Ciri yang dipakai adalah kolom yang hanya ada pada v3, bukan sekadar
  /// keberadaan tabel `data_packages` (tabel itu juga ada pada v1 dan v2).
  static Future<bool> _hasV3Schema(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'users')) return false;
    if (!await _tableExists(db, 'data_packages')) return false;

    final columns = await db.rawQuery('PRAGMA table_info(data_packages)');
    final names = columns.map((row) => row['name']).toSet();

    return names.contains('package_name') &&
        names.contains('advertised_total_quota_bytes') &&
        names.contains('status');
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );

    return rows.isNotEmpty;
  }

  /// Melepas index dan trigger milik sebuah tabel lama.
  ///
  /// SQLite tidak mengganti nama index/trigger saat tabelnya di-RENAME, padahal
  /// skema v2 memakai kembali nama index/trigger v1. Tanpa pelepasan ini,
  /// pembuatan skema v2 gagal (`... already exists`) dan database tidak pernah
  /// bisa dibuka. Hanya objek skema yang dilepas; baris data tidak tersentuh.
  static Future<void> _dropSchemaObjects(
    DatabaseExecutor db,
    String table,
  ) async {
    final objects = await db.rawQuery(
      "SELECT type, name FROM sqlite_master "
      "WHERE tbl_name = ? AND type IN ('index', 'trigger') "
      "AND name NOT LIKE 'sqlite_autoindex%'",
      [table],
    );

    for (final row in objects) {
      final keyword = row['type'] == 'trigger' ? 'TRIGGER' : 'INDEX';
      final name = (row['name'] as String).replaceAll('"', '""');
      await db.execute('DROP $keyword IF EXISTS "$name"');
    }
  }

  /// Seluruh tabel scaffold v1.
  static const List<String> _v1Tables = [
    'data_packages',
    'quota_categories',
    'usage_records',
    'classification_rules',
    'usage_allocations',
    'data_limit_settings',
    'user_settings',
    'alert_logs',
    'app_settings',
  ];

  /// Mengganti nama tabel lama hanya jika tabel tersebut memang ada.
  /// Mengembalikan true jika tabel berhasil diganti nama.
  static Future<bool> _renameIfExists(
    DatabaseExecutor db,
    String from,
    String to,
  ) async {
    if (!await _tableExists(db, from)) return false;
    if (await _tableExists(db, to)) return false;

    await db.execute('ALTER TABLE $from RENAME TO $to');
    return true;
  }

  static Future<void> _createV2Schema(DatabaseExecutor db) async {
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
    // Index dan trigger scaffold v1 memakai nama yang sama dengan v2 dan tidak
    // ikut berganti nama ketika tabelnya di-RENAME. Semuanya dilepas lebih dulu
    // agar pembuatan skema v2 tidak gagal (lihat [_dropSchemaObjects]).
    for (final table in _v1Tables) {
      await _dropSchemaObjects(db, table);
    }

    // Database v1 awal memakai `app_settings`, tetapi beberapa build sempat
    // membuat `user_settings` pada versi yang sama. Keduanya diperiksa agar
    // migrasi tidak gagal hanya karena satu nama tabel berbeda.
    final hasPackages = await _renameIfExists(
      db,
      'data_packages',
      'legacy_data_packages',
    );
    final hasUsage = await _renameIfExists(
      db,
      'usage_records',
      'legacy_usage_records',
    );
    final hasAlerts = await _renameIfExists(
      db,
      'alert_logs',
      'legacy_alert_logs',
    );

    // Seluruh tabel v1 lain diarsipkan agar skema v2 bisa dibuat dan data lama
    // tidak hilang. Isinya tidak lagi dipakai aplikasi.
    await _renameIfExists(db, 'quota_categories', 'legacy_quota_categories');
    await _renameIfExists(
      db,
      'classification_rules',
      'legacy_classification_rules',
    );
    await _renameIfExists(db, 'usage_allocations', 'legacy_usage_allocations');
    await _renameIfExists(
      db,
      'data_limit_settings',
      'legacy_data_limit_settings',
    );
    await _renameIfExists(db, 'app_settings', 'legacy_app_settings');
    await _renameIfExists(db, 'user_settings', 'legacy_user_settings');

    await _createV2Schema(db);

    // Tanpa tabel lama tidak ada data yang perlu dipindahkan.
    if (!hasPackages && !hasUsage && !hasAlerts) return;

    if (hasPackages) {
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
    }

    // Setiap paket lama harus tetap memiliki kategori utama setelah migrasi.
    // Rincian kategori v1 sudah diarsipkan di legacy_quota_categories, sehingga
    // seluruh kuota awal ditempatkan pada satu kategori utama.
    await db.execute('''
      INSERT INTO quota_categories (
        package_id, name, category_type, quota_bytes, created_at, updated_at
      )
      SELECT
        id, 'Kuota Utama', 'main', total_bytes, created_at, updated_at
      FROM data_packages
    ''');

    if (hasUsage) {
      await db.execute('''
        INSERT INTO usage_records (
          id, package_id, record_date, used_bytes, source, updated_at
        )
        SELECT id, package_id, record_date, used_bytes, source, updated_at
        FROM legacy_usage_records
      ''');
    }

    if (hasAlerts) {
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
        CREATE TABLE IF NOT EXISTS legacy_alert_logs_archive AS
        SELECT *
        FROM legacy_alert_logs
        WHERE alert_type NOT IN (
          'daily80', 'daily100', 'dailyOver', 'quota10', 'expiring1d'
        )
      ''');
    }

    // Hapus tabel lama dari yang paling bergantung ke tabel induk.
    if (hasUsage) await db.execute('DROP TABLE legacy_usage_records');
    if (hasAlerts) await db.execute('DROP TABLE legacy_alert_logs');
    if (hasPackages) await db.execute('DROP TABLE legacy_data_packages');

    // legacy_app_settings dan legacy_alert_logs_archive sengaja dipertahankan
    // sebagai arsip. Jangan hapus sebelum pemetaan datanya disepakati.
  }

  static Future<void> _migrateV2ToV3(DatabaseExecutor db) async {
    // Arsipkan seluruh tabel v2.
    // Data lama tetap tersedia jika suatu saat perlu diperiksa.
    await db.execute(
      'ALTER TABLE data_packages RENAME TO legacy_v2_data_packages',
    );
    await db.execute(
      'ALTER TABLE quota_categories RENAME TO legacy_v2_quota_categories',
    );
    await db.execute(
      'ALTER TABLE usage_records RENAME TO legacy_v2_usage_records',
    );
    await db.execute(
      'ALTER TABLE classification_rules RENAME TO legacy_v2_classification_rules',
    );
    await db.execute(
      'ALTER TABLE usage_allocations RENAME TO legacy_v2_usage_allocations',
    );
    await db.execute(
      'ALTER TABLE data_limit_settings RENAME TO legacy_v2_data_limit_settings',
    );
    await db.execute(
      'ALTER TABLE user_settings RENAME TO legacy_v2_user_settings',
    );
    await db.execute('ALTER TABLE alert_logs RENAME TO legacy_v2_alert_logs');

    // Buat struktur database v3.
    await _createV3Schema(db);

    // 1. Buat profil lokal dari UID yang sudah ada.
    await db.execute('''
      INSERT INTO users (
        id,
        display_name,
        email,
        created_at,
        updated_at
      )
      SELECT
        user_id,
        NULL,
        NULL,
        strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
        strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
      FROM (
        SELECT user_id FROM legacy_v2_data_packages
        UNION
        SELECT user_id FROM legacy_v2_user_settings
      )
      WHERE user_id IS NOT NULL
    ''');

    // 2. Migrasikan paket.
    await db.execute('''
      INSERT INTO data_packages (
        id,
        user_id,
        package_name,
        operator_name,
        advertised_total_quota_bytes,
        start_date,
        end_date,
        status,
        created_at,
        updated_at
      )
      SELECT
        'legacy_package_' || id,
        user_id,
        name,
        operator,
        total_bytes,
        start_date,
        end_date,
        CASE
          WHEN is_active = 1 THEN 'ACTIVE'
          ELSE 'INACTIVE'
        END,
        strftime(
          '%Y-%m-%dT%H:%M:%fZ',
          created_at / 1000.0,
          'unixepoch'
        ),
        strftime(
          '%Y-%m-%dT%H:%M:%fZ',
          updated_at / 1000.0,
          'unixepoch'
        )
      FROM legacy_v2_data_packages
    ''');

    // 3. Migrasikan kategori kuota.
    await db.execute('''
      INSERT INTO quota_categories (
        id,
        package_id,
        category_name,
        category_type,
        capacity_bytes,
        valid_from,
        valid_until,
        is_enabled,
        created_at
      )
      SELECT
        'legacy_category_' || id,
        'legacy_package_' || package_id,
        name,
        CASE category_type
          WHEN 'main' THEN 'MAIN'
          WHEN 'night' THEN 'NIGHT'
          WHEN 'social' THEN 'SOCIAL'
          WHEN 'app' THEN 'APP_SPECIFIC'
          WHEN 'custom' THEN 'CUSTOM'
          ELSE 'CUSTOM'
        END,
        quota_bytes,
        NULL,
        NULL,
        1,
        strftime(
          '%Y-%m-%dT%H:%M:%fZ',
          created_at / 1000.0,
          'unixepoch'
        )
      FROM legacy_v2_quota_categories
    ''');

    // Pastikan setiap paket memiliki satu kategori MAIN.
    // Jika kategori lama sudah ada tetapi belum memiliki MAIN,
    // kapasitas kategori MAIN baru dibuat 0 agar tidak menggandakan kuota.
    await db.execute('''
      INSERT INTO quota_categories (
        id,
        package_id,
        category_name,
        category_type,
        capacity_bytes,
        valid_from,
        valid_until,
        is_enabled,
        created_at
      )
      SELECT
        'legacy_main_' || p.id,
        p.id,
        'Kuota Utama',
        'MAIN',
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM quota_categories AS q
            WHERE q.package_id = p.id
          ) THEN 0
          ELSE p.advertised_total_quota_bytes
        END,
        NULL,
        NULL,
        1,
        p.created_at
      FROM data_packages AS p
      WHERE NOT EXISTS (
        SELECT 1
        FROM quota_categories AS q
        WHERE q.package_id = p.id
          AND q.category_type = 'MAIN'
      )
    ''');

    // 4. Migrasikan catatan penggunaan lama.
    //
    // Data otomatis lama tidak memiliki rincian aplikasi.
    // Karena itu, data tersebut masuk sebagai DEVICE_TOTAL.
    // Data manual masuk sebagai MANUAL_TOTAL.
    await db.execute('''
      INSERT INTO usage_records (
        id,
        package_id,
        record_scope,
        app_uid,
        app_package_name,
        app_name,
        network_type,
        period_start_at,
        period_end_at,
        rx_bytes,
        tx_bytes,
        source,
        source_key,
        recorded_at
      )
      SELECT
        'legacy_usage_' || id,
        'legacy_package_' || package_id,
        CASE
          WHEN source = 'manual' THEN 'MANUAL_TOTAL'
          ELSE 'DEVICE_TOTAL'
        END,
        NULL,
        NULL,
        NULL,
        'MOBILE',
        record_date || 'T00:00:00.000Z',
        record_date || 'T23:59:59.999Z',
        used_bytes,
        0,
        CASE
          WHEN source = 'manual' THEN 'MANUAL'
          ELSE 'ANDROID'
        END,
        CASE
          WHEN source = 'manual' THEN NULL
          ELSE 'legacy_usage_' || id
        END,
        strftime(
          '%Y-%m-%dT%H:%M:%fZ',
          updated_at / 1000.0,
          'unixepoch'
        )
      FROM legacy_v2_usage_records
    ''');

    // Manual usage records in v2 had no category field. Preserve their
    // bytes as an explicit UNCLASSIFIED allocation in the v3 operational model.
    await db.execute('''
      INSERT INTO usage_allocations (
        id,
        package_id,
        usage_record_id,
        quota_category_id,
        classification_rule_id,
        allocated_bytes,
        allocation_method,
        created_at
      )
      SELECT
        'legacy_manual_allocation_' || id,
        'legacy_package_' || package_id,
        'legacy_usage_' || id,
        NULL,
        NULL,
        used_bytes,
        'UNCLASSIFIED',
        strftime(
          '%Y-%m-%dT%H:%M:%fZ',
          updated_at / 1000.0,
          'unixepoch'
        )
      FROM legacy_v2_usage_records
      WHERE LOWER(source) = 'manual'
    ''');

    // 5. Migrasikan aturan klasifikasi.
    await db.execute('''
      INSERT INTO classification_rules (
        id,
        quota_category_id,
        rule_name,
        app_package_name,
        start_minute,
        end_minute,
        days_of_week_mask,
        priority,
        is_enabled,
        created_at
      )
      SELECT
        'legacy_rule_' || r.id,
        'legacy_category_' || r.category_id,
        'Aturan lama ' || r.id,
        NULLIF(r.app_package_name, ''),
        r.start_minute,
        r.end_minute,
        127,
        r.priority,
        r.is_enabled,
        strftime(
          '%Y-%m-%dT%H:%M:%fZ',
          r.created_at / 1000.0,
          'unixepoch'
        )
      FROM legacy_v2_classification_rules AS r
      INNER JOIN quota_categories AS q
        ON q.id = 'legacy_category_' || r.category_id
    ''');

    // 6. Migrasikan pengaturan batas penggunaan.
    await db.execute('''
      INSERT INTO data_limit_settings (
        package_id,
        daily_limit_bytes,
        warn_at_percent,
        limit_at_percent,
        is_enabled,
        updated_at
      )
      SELECT
        'legacy_package_' || package_id,
        NULL,
        quota_warning_percent,
        100,
        is_enabled,
        strftime(
          '%Y-%m-%dT%H:%M:%fZ',
          updated_at / 1000.0,
          'unixepoch'
        )
      FROM legacy_v2_data_limit_settings
    ''');

    // 7. Migrasikan pengaturan pengguna.
    await db.execute('''
      INSERT INTO user_settings (
        user_id,
        theme_mode,
        palette_key,
        notifications_enabled,
        timezone_id,
        updated_at
      )
      SELECT
        u.id,

        CASE UPPER(
          COALESCE(
            MAX(
              CASE
                WHEN s.key = 'theme_mode' THEN s.value
              END
            ),
            'LIGHT'
          )
        )
          WHEN 'DARK' THEN 'DARK'
          ELSE 'LIGHT'
        END,

        COALESCE(
          MAX(
            CASE
              WHEN s.key = 'palette_key' THEN s.value
            END
          ),
          'BLUE'
        ),

        CASE
          WHEN COALESCE(
            MAX(
              CASE
                WHEN s.key = 'notif_enabled' THEN s.value
              END
            ),
            '1'
          ) IN ('1', 'true', 'TRUE') THEN 1
          ELSE 0
        END,

        COALESCE(
          MAX(
            CASE
              WHEN s.key = 'timezone_id' THEN s.value
            END
          ),
          'UTC'
        ),

        strftime('%Y-%m-%dT%H:%M:%fZ', 'now')

      FROM users AS u
      LEFT JOIN legacy_v2_user_settings AS s
        ON s.user_id = u.id
      GROUP BY u.id
    ''');

    // 8. Migrasikan riwayat alert.
    await db.execute('''
      INSERT INTO alert_logs (
        id,
        package_id,
        quota_category_id,
        alert_type,
        message,
        observed_bytes,
        threshold_bytes,
        dedupe_key,
        triggered_at,
        is_read
      )
      SELECT
        'legacy_alert_' || id,
        'legacy_package_' || package_id,
        NULL,
        alert_type,
        'Peringatan lama: ' || alert_type,
        NULL,
        NULL,
        'legacy_alert_' || id,
        strftime(
          '%Y-%m-%dT%H:%M:%fZ',
          sent_at / 1000.0,
          'unixepoch'
        ),
        0
      FROM legacy_v2_alert_logs
    ''');
  }

  static Future<void> _createV3Schema(DatabaseExecutor db) async {
    for (final sql in _v3CreateStatements) {
      await db.execute(sql);
    }

    for (final sql in _v3IndexStatements) {
      await db.execute(sql);
    }

    for (final sql in _v3TriggerStatements) {
      await db.execute(sql);
    }
  }

  static const List<String> _v3CreateStatements = [
    '''
    CREATE TABLE users (
      id TEXT PRIMARY KEY NOT NULL,
      display_name TEXT,
      email TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',

    '''
    CREATE TABLE data_packages (
      id TEXT PRIMARY KEY NOT NULL,
      user_id TEXT NOT NULL,
      package_name TEXT NOT NULL,
      operator_name TEXT,
      advertised_total_quota_bytes INTEGER NOT NULL
        CHECK (advertised_total_quota_bytes >= 0),
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      status TEXT NOT NULL
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'EXPIRED', 'ARCHIVED')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (end_date >= start_date),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
    ''',

    '''
    CREATE TABLE quota_categories (
      id TEXT PRIMARY KEY NOT NULL,
      package_id TEXT NOT NULL,
      category_name TEXT NOT NULL,
      category_type TEXT NOT NULL
        CHECK (category_type IN (
          'MAIN', 'NIGHT', 'SOCIAL', 'APP_SPECIFIC', 'CUSTOM'
        )),
      capacity_bytes INTEGER NOT NULL CHECK (capacity_bytes >= 0),
      valid_from TEXT,
      valid_until TEXT,
      is_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (is_enabled IN (0, 1)),
      created_at TEXT NOT NULL,
      UNIQUE (id, package_id),
      CHECK (
        valid_until IS NULL
        OR valid_from IS NULL
        OR valid_until >= valid_from
      ),
      FOREIGN KEY (package_id)
        REFERENCES data_packages(id) ON DELETE CASCADE
    )
    ''',

    '''
    CREATE TABLE usage_records (
      id TEXT PRIMARY KEY NOT NULL,
      package_id TEXT NOT NULL,
      record_scope TEXT NOT NULL
        CHECK (record_scope IN (
          'APP_USAGE', 'DEVICE_TOTAL', 'MANUAL_TOTAL'
        )),
      app_uid INTEGER,
      app_package_name TEXT,
      app_name TEXT,
      network_type TEXT NOT NULL
        CHECK (network_type IN ('MOBILE', 'WIFI', 'UNKNOWN')),
      period_start_at TEXT NOT NULL,
      period_end_at TEXT NOT NULL,
      rx_bytes INTEGER NOT NULL DEFAULT 0 CHECK (rx_bytes >= 0),
      tx_bytes INTEGER NOT NULL DEFAULT 0 CHECK (tx_bytes >= 0),
      source TEXT NOT NULL CHECK (source IN ('ANDROID', 'MANUAL')),
      source_key TEXT UNIQUE,
      recorded_at TEXT NOT NULL,
      UNIQUE (id, package_id),
      CHECK (period_end_at >= period_start_at),
      CHECK (source = 'MANUAL' OR source_key IS NOT NULL),
      FOREIGN KEY (package_id)
        REFERENCES data_packages(id) ON DELETE CASCADE
    )
    ''',

    '''
    CREATE TABLE classification_rules (
      id TEXT PRIMARY KEY NOT NULL,
      quota_category_id TEXT NOT NULL,
      rule_name TEXT NOT NULL,
      app_package_name TEXT,
      start_minute INTEGER,
      end_minute INTEGER,
      days_of_week_mask INTEGER NOT NULL DEFAULT 127
        CHECK (days_of_week_mask BETWEEN 1 AND 127),
      priority INTEGER NOT NULL DEFAULT 0,
      is_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (is_enabled IN (0, 1)),
      created_at TEXT NOT NULL,
      UNIQUE (id, quota_category_id),
      CHECK (
        start_minute IS NULL
        OR start_minute BETWEEN 0 AND 1439
      ),
      CHECK (
        end_minute IS NULL
        OR end_minute BETWEEN 0 AND 1440
      ),
      CHECK (
        (start_minute IS NULL AND end_minute IS NULL)
        OR
        (start_minute IS NOT NULL AND end_minute IS NOT NULL)
      ),
      FOREIGN KEY (quota_category_id)
        REFERENCES quota_categories(id) ON DELETE RESTRICT
    )
    ''',

    '''
    CREATE TABLE usage_allocations (
      id TEXT PRIMARY KEY NOT NULL,
      package_id TEXT NOT NULL,
      usage_record_id TEXT NOT NULL,
      quota_category_id TEXT,
      classification_rule_id TEXT,
      allocated_bytes INTEGER NOT NULL
        CHECK (allocated_bytes >= 0),
      allocation_method TEXT NOT NULL
        CHECK (allocation_method IN (
          'AUTO_RULE',
          'MAIN_FALLBACK',
          'MANUAL_USER',
          'UNCLASSIFIED'
        )),
      created_at TEXT NOT NULL,

      CHECK (
        (allocation_method = 'UNCLASSIFIED'
          AND quota_category_id IS NULL)
        OR
        (allocation_method <> 'UNCLASSIFIED'
          AND quota_category_id IS NOT NULL)
      ),

      CHECK (
        (allocation_method = 'AUTO_RULE'
          AND classification_rule_id IS NOT NULL)
        OR
        (allocation_method <> 'AUTO_RULE'
          AND classification_rule_id IS NULL)
      ),

      FOREIGN KEY (usage_record_id, package_id)
        REFERENCES usage_records(id, package_id) ON DELETE CASCADE,

      FOREIGN KEY (quota_category_id, package_id)
        REFERENCES quota_categories(id, package_id) ON DELETE RESTRICT,

      FOREIGN KEY (classification_rule_id, quota_category_id)
        REFERENCES classification_rules(id, quota_category_id)
        ON DELETE RESTRICT
    )
    ''',

    '''
    CREATE TABLE data_limit_settings (
      package_id TEXT PRIMARY KEY NOT NULL,
      daily_limit_bytes INTEGER
        CHECK (
          daily_limit_bytes IS NULL
          OR daily_limit_bytes >= 0
        ),
      warn_at_percent INTEGER NOT NULL DEFAULT 80
        CHECK (warn_at_percent BETWEEN 1 AND 100),
      limit_at_percent INTEGER NOT NULL DEFAULT 100
        CHECK (limit_at_percent BETWEEN 1 AND 100),
      is_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (is_enabled IN (0, 1)),
      updated_at TEXT NOT NULL,
      FOREIGN KEY (package_id)
        REFERENCES data_packages(id) ON DELETE CASCADE
    )
    ''',

    '''
    CREATE TABLE user_settings (
      user_id TEXT PRIMARY KEY NOT NULL,
      theme_mode TEXT NOT NULL DEFAULT 'LIGHT'
        CHECK (theme_mode IN ('LIGHT', 'DARK')),
      palette_key TEXT NOT NULL DEFAULT 'BLUE',
      notifications_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (notifications_enabled IN (0, 1)),
      timezone_id TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
    )
    ''',

    '''
    CREATE TABLE alert_logs (
      id TEXT PRIMARY KEY NOT NULL,
      package_id TEXT NOT NULL,
      quota_category_id TEXT,
      alert_type TEXT NOT NULL,
      message TEXT NOT NULL,
      observed_bytes INTEGER,
      threshold_bytes INTEGER,
      dedupe_key TEXT NOT NULL UNIQUE,
      triggered_at TEXT NOT NULL,
      is_read INTEGER NOT NULL DEFAULT 0
        CHECK (is_read IN (0, 1)),
      FOREIGN KEY (package_id)
        REFERENCES data_packages(id) ON DELETE CASCADE,
      FOREIGN KEY (quota_category_id, package_id)
        REFERENCES quota_categories(id, package_id) ON DELETE RESTRICT
    )
    ''',
  ];

  static const List<String> _v3IndexStatements = [
    '''
    CREATE UNIQUE INDEX uq_one_active_package_per_user
    ON data_packages(user_id)
    WHERE status = 'ACTIVE'
    ''',

    '''
    CREATE INDEX idx_packages_user_status
    ON data_packages(user_id, status)
    ''',

    '''
    CREATE UNIQUE INDEX uq_one_main_category_per_package
    ON quota_categories(package_id)
    WHERE category_type = 'MAIN'
    ''',

    '''
    CREATE INDEX idx_categories_package
    ON quota_categories(package_id)
    ''',

    '''
    CREATE INDEX idx_usage_package_period
    ON usage_records(package_id, period_start_at, period_end_at)
    ''',

    '''
    CREATE INDEX idx_usage_package_app
    ON usage_records(package_id, app_package_name)
    ''',

    '''
    CREATE INDEX idx_rules_category_priority
    ON classification_rules(
      quota_category_id,
      is_enabled,
      priority
    )
    ''',

    '''
    CREATE INDEX idx_allocations_category
    ON usage_allocations(quota_category_id)
    ''',

    '''
    CREATE INDEX idx_allocations_usage
    ON usage_allocations(usage_record_id)
    ''',

    '''
    CREATE INDEX idx_alerts_package_time
    ON alert_logs(package_id, triggered_at)
    ''',
  ];

  static const List<String> _v3TriggerStatements = [
    '''
    CREATE TRIGGER validate_v3_category_total_insert
    BEFORE INSERT ON quota_categories
    WHEN
      COALESCE((
        SELECT SUM(capacity_bytes)
        FROM quota_categories
        WHERE package_id = NEW.package_id
      ), 0) + NEW.capacity_bytes > (
        SELECT advertised_total_quota_bytes
        FROM data_packages
        WHERE id = NEW.package_id
      )
    BEGIN
      SELECT RAISE(
        ABORT,
        'category capacities exceed package quota'
      );
    END
    ''',

    '''
    CREATE TRIGGER validate_v3_category_total_update
    BEFORE UPDATE OF package_id, capacity_bytes ON quota_categories
    WHEN
      COALESCE((
        SELECT SUM(capacity_bytes)
        FROM quota_categories
        WHERE package_id = NEW.package_id
          AND id != OLD.id
      ), 0) + NEW.capacity_bytes > (
        SELECT advertised_total_quota_bytes
        FROM data_packages
        WHERE id = NEW.package_id
      )
    BEGIN
      SELECT RAISE(
        ABORT,
        'category capacities exceed package quota'
      );
    END
    ''',

    '''
    CREATE TRIGGER prevent_invalid_allocation_insert
    BEFORE INSERT ON usage_allocations
    WHEN
      NOT EXISTS (
        SELECT 1
        FROM usage_records
        WHERE id = NEW.usage_record_id
          AND package_id = NEW.package_id
          AND record_scope <> 'DEVICE_TOTAL'
          AND network_type <> 'WIFI'
      )
    BEGIN
      SELECT RAISE(
        ABORT,
        'DEVICE_TOTAL or WIFI usage cannot be allocated'
      );
    END
    ''',

    '''
    CREATE TRIGGER prevent_invalid_allocation_update
    BEFORE UPDATE OF usage_record_id, package_id ON usage_allocations
    WHEN
      NOT EXISTS (
        SELECT 1
        FROM usage_records
        WHERE id = NEW.usage_record_id
          AND package_id = NEW.package_id
          AND record_scope <> 'DEVICE_TOTAL'
          AND network_type <> 'WIFI'
      )
    BEGIN
      SELECT RAISE(
        ABORT,
        'DEVICE_TOTAL or WIFI usage cannot be allocated'
      );
    END
    ''',

    '''
    CREATE TRIGGER validate_v3_allocation_total_insert
    BEFORE INSERT ON usage_allocations
    WHEN
      NEW.allocated_bytes + COALESCE((
        SELECT SUM(allocated_bytes)
        FROM usage_allocations
        WHERE usage_record_id = NEW.usage_record_id
      ), 0) > (
        SELECT rx_bytes + tx_bytes
        FROM usage_records
        WHERE id = NEW.usage_record_id
      )
    BEGIN
      SELECT RAISE(
        ABORT,
        'allocation total exceeds usage record'
      );
    END
    ''',

    '''
    CREATE TRIGGER validate_v3_allocation_total_update
    BEFORE UPDATE OF usage_record_id, allocated_bytes
    ON usage_allocations
    WHEN
      NEW.allocated_bytes + COALESCE((
        SELECT SUM(allocated_bytes)
        FROM usage_allocations
        WHERE usage_record_id = NEW.usage_record_id
          AND id != OLD.id
      ), 0) > (
        SELECT rx_bytes + tx_bytes
        FROM usage_records
        WHERE id = NEW.usage_record_id
      )
    BEGIN
      SELECT RAISE(
        ABORT,
        'allocation total exceeds usage record'
      );
    END
    ''',

    '''
    CREATE TRIGGER validate_v3_usage_update
    BEFORE UPDATE OF rx_bytes, tx_bytes ON usage_records
    WHEN
      COALESCE((
        SELECT SUM(allocated_bytes)
        FROM usage_allocations
        WHERE usage_record_id = OLD.id
      ), 0) > NEW.rx_bytes + NEW.tx_bytes
    BEGIN
      SELECT RAISE(
        ABORT,
        'usage record is below its allocations'
      );
    END
    ''',
    '''
    CREATE TRIGGER prevent_invalid_usage_scope_update
    BEFORE UPDATE OF record_scope, network_type ON usage_records
    WHEN
      (
        NEW.record_scope = 'DEVICE_TOTAL'
        OR NEW.network_type = 'WIFI'
      )
      AND EXISTS (
        SELECT 1
        FROM usage_allocations
        WHERE usage_record_id = OLD.id
      )
    BEGIN
      SELECT RAISE(
        ABORT,
        'usage record with allocations cannot become DEVICE_TOTAL or WIFI'
      );
    END
    ''',
  ];

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
