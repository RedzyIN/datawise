// MILIK ARSITEK. KONTRAK BEKU #2 - Database. Dipakai mulai minggu 2.
// Hanya implementasi repository sqflite yang boleh memakai kelas ini.
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
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final sql in _createStatements) {
          await db.execute(sql);
        }
      },
      // Perubahan struktur di kemudian hari: HANYA Arsitek, lewat onUpgrade.
    );
  }

  static const List<String> _createStatements = [
    '''
CREATE TABLE data_packages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  operator TEXT NOT NULL,
  total_bytes INTEGER NOT NULL CHECK (total_bytes > 0),
  initial_used_bytes INTEGER NOT NULL DEFAULT 0 CHECK (initial_used_bytes >= 0),
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  price INTEGER,
  is_active INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''',
    'CREATE INDEX idx_pkg_user ON data_packages(user_id, is_active)',
    '''
CREATE TABLE usage_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
  record_date TEXT NOT NULL,
  used_bytes INTEGER NOT NULL CHECK (used_bytes >= 0),
  source TEXT NOT NULL CHECK (source IN ('auto','manual')),
  updated_at INTEGER NOT NULL,
  UNIQUE (package_id, record_date, source)
)''',
    '''
CREATE TABLE alert_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
  alert_type TEXT NOT NULL,
  alert_date TEXT NOT NULL,
  sent_at INTEGER NOT NULL,
  UNIQUE (package_id, alert_type, alert_date)
)''',
    '''
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''',
  ];
}
