/// Struktur tabel users dan data_packages.
/// Tambahkan kedua statement ini ke onCreate / migrasi DbHelper
/// (users harus dibuat lebih dulu daripada data_packages).
class PackageSchema {
  static const String createUsers = '''
CREATE TABLE IF NOT EXISTS users (
  id           TEXT PRIMARY KEY,            -- Firebase UID
  display_name TEXT,
  email        TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
)
''';

  static const String createDataPackages = '''
CREATE TABLE IF NOT EXISTS data_packages (
  id                          TEXT PRIMARY KEY,
  user_id                     TEXT NOT NULL,
  package_name                TEXT NOT NULL CHECK (length(trim(package_name)) > 0),
  operator_name               TEXT,
  advertised_total_quota_bytes INTEGER NOT NULL CHECK (advertised_total_quota_bytes > 0),
  start_date                  TEXT NOT NULL,
  end_date                    TEXT NOT NULL,
  status                      TEXT NOT NULL
                              CHECK (status IN ('ACTIVE','INACTIVE','EXPIRED','ARCHIVED')),
  created_at                  TEXT NOT NULL,
  updated_at                  TEXT NOT NULL,
  CHECK (end_date >= start_date),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
)
''';

  static const String indexUserPackages =
      'CREATE INDEX IF NOT EXISTS idx_data_packages_user '
      'ON data_packages(user_id, created_at DESC)';

  /// Menjamin hanya ada satu paket ACTIVE untuk setiap pengguna.
  static const String uniqueActivePerUser =
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_data_packages_one_active '
      "ON data_packages(user_id) WHERE status = 'ACTIVE'";

  static const List<String> all = [
    createUsers,
    createDataPackages,
    indexUserPackages,
    uniqueActivePerUser,
  ];
}
