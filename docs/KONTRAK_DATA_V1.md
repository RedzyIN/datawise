# DATAWISE — Kontrak Data v1.0 (DIBEKUKAN)

Status: kontrak acuan untuk seluruh anggota.  
Target branch: `develop` melalui pull request.  
Platform: Android, minSdk 29.  
Kontrak data: v1.0. Database SQLite `datawise.db`, versi skema implementasi 2. Versi skema 2 digunakan untuk migrasi dari scaffold lama, bukan perubahan kontrak data.  
Satuan kuota dan pemakaian: byte desimal, 1 GB = 1.000.000.000 byte.

Dokumen ini menjadi satu-satunya acuan untuk struktur database, bentuk model Dart, dan antarmuka repository. Jika ada dokumen anggota atau kode lama yang berbeda, ikuti dokumen ini. Jangan mengubah nama field, tipe data, enum, atau tanda tangan method tanpa persetujuan arsitek dan pembaruan versi kontrak.

## 1. Keputusan inti

1. Firebase Authentication menjadi sumber identitas. `user_id` menyimpan Firebase UID sebagai TEXT. Tidak ada tabel `users` lokal.
2. Semua ID entitas lokal memakai `INTEGER PRIMARY KEY AUTOINCREMENT`. Firebase UID tetap TEXT.
3. Satu pengguna hanya boleh memiliki satu paket aktif pada satu waktu.
4. Satu paket memiliki satu kategori utama (`main`) dan nol atau lebih kategori tambahan (`night`, `social`, `app`, `custom`).
5. Jumlah kuota semua kategori dalam satu paket harus sama dengan `data_packages.total_bytes`. Kuota kategori utama adalah sisa setelah kuota kategori tambahan dikurangkan.
6. Pemakaian harian memiliki sumber `auto` atau `manual`. Jika keduanya tersedia pada tanggal yang sama, `manual` menjadi nilai efektif dan menggantikan `auto`. Keduanya tidak dijumlahkan.
7. Alokasi kategori berasal dari proses klasifikasi. Total alokasi satu record tidak boleh melebihi `usage_records.used_bytes`. Sisa yang tidak cocok dengan aturan klasifikasi masuk kategori `main`.
8. Aturan klasifikasi menggunakan nama paket aplikasi Android, rentang waktu, dan prioritas. Tidak menggunakan machine learning.
9. Peringatan batas kuota hanya memberi notifikasi. Aplikasi tidak mematikan data seluler.
10. Database lokal tetap menjadi sumber data operasional. Firebase hanya untuk autentikasi pada MVP, tanpa Firestore atau sinkronisasi cloud.

## 2. Database v1

Catatan versi: istilah Database v1 pada bagian ini merujuk pada kontrak data v1.0. Implementasi SQLite menggunakan `dbVersion = 2` karena skema scaffold lama perlu dimigrasikan ke delapan tabel kontrak.

Delapan tabel berikut wajib tersedia. Nama kolom menggunakan snake_case.

### 2.1 `data_packages`

| Kolom | Tipe | Aturan |
|---|---|---|
| id | INTEGER | PK AUTOINCREMENT |
| user_id | TEXT | NOT NULL, Firebase UID |
| name | TEXT | NOT NULL |
| operator | TEXT | NOT NULL |
| total_bytes | INTEGER | NOT NULL, > 0 |
| initial_used_bytes | INTEGER | NOT NULL, default 0, >= 0 |
| start_date | TEXT | NOT NULL, YYYY-MM-DD |
| end_date | TEXT | NOT NULL, YYYY-MM-DD, harus setelah start_date |
| price | INTEGER | nullable, rupiah |
| is_active | INTEGER | NOT NULL, 0 atau 1 |
| created_at | INTEGER | NOT NULL, Unix epoch milliseconds UTC |
| updated_at | INTEGER | NOT NULL, Unix epoch milliseconds UTC |

Index: `(user_id, is_active)`. Aturan satu paket aktif per pengguna harus dijaga dalam transaksi repository. Jangan mengandalkan UI untuk menjaga aturan ini.

### 2.2 `quota_categories`

| Kolom | Tipe | Aturan |
|---|---|---|
| id | INTEGER | PK AUTOINCREMENT |
| package_id | INTEGER | NOT NULL, FK data_packages ON DELETE CASCADE |
| name | TEXT | NOT NULL |
| category_type | TEXT | NOT NULL: main, night, social, app, custom |
| quota_bytes | INTEGER | NOT NULL, > 0 |
| start_minute | INTEGER | nullable, 0–1439 |
| end_minute | INTEGER | nullable, 0–1439 |
| created_at | INTEGER | NOT NULL, milliseconds UTC |
| updated_at | INTEGER | NOT NULL, milliseconds UTC |

Constraint: UNIQUE(package_id, name). Maksimal satu kategori `main` per paket. Kategori `main` wajib ada. Untuk kategori yang tidak dibatasi jam, kedua kolom waktu bernilai NULL. Untuk rentang melewati tengah malam, misalnya 23:00–06:00, start_minute lebih besar daripada end_minute.

### 2.3 `usage_records`

| Kolom | Tipe | Aturan |
|---|---|---|
| id | INTEGER | PK AUTOINCREMENT |
| package_id | INTEGER | NOT NULL, FK data_packages ON DELETE CASCADE |
| record_date | TEXT | NOT NULL, YYYY-MM-DD |
| used_bytes | INTEGER | NOT NULL, >= 0 |
| source | TEXT | NOT NULL: auto atau manual |
| updated_at | INTEGER | NOT NULL, milliseconds UTC |

Constraint: UNIQUE(package_id, record_date, source). Satu tanggal boleh memiliki satu record auto dan satu record manual.

### 2.4 `classification_rules`

| Kolom | Tipe | Aturan |
|---|---|---|
| id | INTEGER | PK AUTOINCREMENT |
| package_id | INTEGER | NOT NULL, FK data_packages ON DELETE CASCADE |
| category_id | INTEGER | NOT NULL, FK quota_categories ON DELETE CASCADE |
| app_package_name | TEXT | NOT NULL, nama paket Android |
| start_minute | INTEGER | nullable, 0–1439 |
| end_minute | INTEGER | nullable, 0–1439 |
| priority | INTEGER | NOT NULL, angka lebih kecil berarti lebih dahulu |
| is_enabled | INTEGER | NOT NULL, 0 atau 1 |
| created_at | INTEGER | NOT NULL, milliseconds UTC |
| updated_at | INTEGER | NOT NULL, milliseconds UTC |

Satu rule hanya berlaku pada paket yang sama dengan kategori tujuannya. Validasi relasi ini dilakukan repository/service karena SQLite tidak dapat memastikan kesamaan package_id dari dua tabel melalui FK biasa. Jika beberapa rule cocok, pilih priority terkecil. Jika prioritas sama, pilih ID terkecil. Jika tidak ada rule cocok, alokasikan ke kategori main.

### 2.5 `usage_allocations`

| Kolom | Tipe | Aturan |
|---|---|---|
| id | INTEGER | PK AUTOINCREMENT |
| usage_record_id | INTEGER | NOT NULL, FK usage_records ON DELETE CASCADE |
| category_id | INTEGER | NOT NULL, FK quota_categories ON DELETE CASCADE |
| app_package_name | TEXT | NOT NULL, string kosong untuk alokasi agregat/non-app |
| used_bytes | INTEGER | NOT NULL, >= 0 |

Constraint: UNIQUE(usage_record_id, category_id, app_package_name). Satu record boleh memiliki banyak alokasi. Alokasi kategori harus berasal dari paket yang sama dengan usage record. Validasi dilakukan di repository/service. Saat record auto diperbarui, alokasi auto lama untuk record tersebut diganti dalam satu transaksi. Record manual tidak dianggap sebagai rincian aplikasi.

### 2.6 `data_limit_settings`

| Kolom | Tipe | Aturan |
|---|---|---|
| id | INTEGER | PK AUTOINCREMENT |
| package_id | INTEGER | NOT NULL, UNIQUE, FK data_packages ON DELETE CASCADE |
| daily_warning_percent | INTEGER | NOT NULL, default 100, > 0 |
| quota_warning_percent | INTEGER | NOT NULL, default 10, 1–100 |
| is_enabled | INTEGER | NOT NULL, default 1, 0 atau 1 |
| updated_at | INTEGER | NOT NULL, milliseconds UTC |

Pengaturan ini hanya mengendalikan peringatan. Tidak ada tindakan memutus koneksi.

### 2.7 `user_settings`

| Kolom | Tipe | Aturan |
|---|---|---|
| user_id | TEXT | NOT NULL |
| key | TEXT | NOT NULL |
| value | TEXT | NOT NULL |

Primary key gabungan: `(user_id, key)`. Nilai disimpan sebagai TEXT. Boolean menggunakan `'1'` atau `'0'`. Kunci yang sudah ditetapkan: `notif_enabled`, `last_usage_refresh`, `theme_mode`, `theme_palette`.

### 2.8 `alert_logs`

| Kolom | Tipe | Aturan |
|---|---|---|
| id | INTEGER | PK AUTOINCREMENT |
| package_id | INTEGER | NOT NULL, FK data_packages ON DELETE CASCADE |
| alert_type | TEXT | NOT NULL: daily80, daily100, dailyOver, quota10, expiring1d |
| alert_date | TEXT | NOT NULL, YYYY-MM-DD |
| sent_at | INTEGER | NOT NULL, milliseconds UTC |

Constraint: UNIQUE(package_id, alert_type, alert_date). Untuk alert quota10 dan expiring1d, alert_date menggunakan tanggal pemicu yang ditetapkan oleh AlertService. Repository tidak menentukan aturan pemicu.

## 3. Aturan waktu dan perhitungan

- Tanggal paket dan tanggal record disimpan sebagai tanggal lokal `YYYY-MM-DD`, tanpa jam.
- Timestamp audit disimpan sebagai Unix epoch milliseconds UTC.
- `initial_used_bytes` adalah pemakaian sebelum pencatatan harian dimulai.
- Pemakaian efektif satu tanggal adalah record manual jika tersedia. Jika tidak, gunakan record auto. Jika tidak ada keduanya, nilainya nol.
- Total pemakaian paket = `initial_used_bytes` + jumlah pemakaian efektif semua tanggal.
- Sisa kuota = max(0, total_bytes - total_used_bytes). Nilai pemakaian tetap boleh melampaui total kuota agar kondisi over-quota dapat ditampilkan.
- Total pemakaian kategori dihitung dari usage_allocations pada record efektif. Jangan menjumlahkan alokasi dari record auto dan manual pada tanggal yang sama.
- 1 GB = 1.000.000.000 byte. Jangan memakai 1.073.741.824 sebagai konversi GB.

## 4. Kontrak model Dart

Semua model bersifat data-only. Model tidak boleh mengakses SQLite, Firebase, Android, Provider, atau melakukan perhitungan bisnis. Serialisasi `toMap/fromMap` hanya dipakai repository.

| Model | Field wajib |
|---|---|
| AppUser | String uid, String email |
| DataPackage | int? id, String userId, String name, String operator, int totalBytes, int initialUsedBytes, DateTime startDate, DateTime endDate, int? price, bool isActive, DateTime createdAt, DateTime updatedAt |
| QuotaCategory | int? id, int packageId, String name, QuotaCategoryType type, int quotaBytes, int? startMinute, int? endMinute, DateTime createdAt, DateTime updatedAt |
| UsageRecord | int? id, int packageId, DateTime recordDate, int usedBytes, UsageSource source, DateTime updatedAt |
| ClassificationRule | int? id, int packageId, int categoryId, String appPackageName, int? startMinute, int? endMinute, int priority, bool isEnabled, DateTime createdAt, DateTime updatedAt |
| UsageAllocation | int? id, int usageRecordId, int categoryId, String appPackageName, int usedBytes |
| DataLimitSetting | int? id, int packageId, int dailyWarningPercent, int quotaWarningPercent, bool isEnabled, DateTime updatedAt |
| AlertLog | int? id, int packageId, AlertType type, DateTime alertDate, DateTime sentAt |
| UserSetting | String userId, String key, String value |

Enum beku:
- UsageSource: auto, manual
- UsageReadStatus: ok, permissionDenied, unsupported, error
- PlannerStatus: normal, notStarted, depleted, expired
- AlertType: daily80, daily100, dailyOver, quota10, expiring1d
- QuotaCategoryType: main, night, social, app, custom

Model hasil layanan:
- UsageReading: UsageReadStatus status, int totalBytes, DateTime start, DateTime end, String? message.
- PlannerResult: PlannerStatus status, int totalBytes, int usedBytes, int remainingBytes, int remainingDays, double? dailyTargetBytes, double? weeklyTargetBytes, int todayUsedBytes, double usagePercent, double? todayPercentOfTarget.
- AppException: String code, String message. Kode: validation, not_found, db_error, permission_denied, native_error, auth_error, unknown.

Semua ID lokal memakai int. Jangan membuat UUID/String ID untuk tabel lokal. Firebase UID tetap String.

## 5. Kontrak repository Dart

Repository adalah satu-satunya lapisan yang boleh membaca/menulis database. Semua method asynchronous. Repository mengembalikan model atau nilai sederhana, bukan Map mentah. Repository melempar AppException dengan kode yang sesuai untuk kegagalan yang bisa ditangani aplikasi.

### PackageRepository
- Future<int> add(DataPackage package)
- Future<void> update(DataPackage package)
- Future<void> delete(int packageId)
- Future<DataPackage?> getById(int packageId)
- Future<DataPackage?> getActive(String userId)
- Future<List<DataPackage>> getAll(String userId)
- Future<void> setActive(String userId, int packageId)

### QuotaCategoryRepository
- Future<int> add(QuotaCategory category)
- Future<void> update(QuotaCategory category)
- Future<void> delete(int categoryId)
- Future<QuotaCategory?> getById(int categoryId)
- Future<List<QuotaCategory>> getByPackage(int packageId)

### UsageRepository
- Future<void> upsertRecord(int packageId, DateTime date, int usedBytes, UsageSource source)
- Future<void> deleteManual(int packageId, DateTime date)
- Future<UsageRecord?> getEffectiveRecord(int packageId, DateTime date)
- Future<List<UsageRecord>> getEffectiveRecords(int packageId)
- Future<List<UsageRecord>> getRecords(int packageId)
- Future<int> getUsedBytesOn(int packageId, DateTime date)
- Future<int> getTotalUsedBytes(int packageId)
- Future<Map<DateTime, int>> getDailyUsage(int packageId)
- Future<void> replaceAllocations(int usageRecordId, List<UsageAllocation> allocations)
- Future<List<UsageAllocation>> getAllocations(int usageRecordId)
- Future<Map<int, int>> getCategoryUsage(int packageId)

### ClassificationRuleRepository
- Future<int> add(ClassificationRule rule)
- Future<void> update(ClassificationRule rule)
- Future<void> delete(int ruleId)
- Future<List<ClassificationRule>> getByPackage(int packageId)

### DataLimitRepository
- Future<DataLimitSetting?> getByPackage(int packageId)
- Future<void> upsert(DataLimitSetting setting)

### SettingsRepository
- Future<String?> get(String userId, String key)
- Future<void> set(String userId, String key, String value)
- Future<void> delete(String userId, String key)

### AlertRepository
- Future<bool> hasBeenSent(int packageId, AlertType type, DateTime alertDate)
- Future<void> markSent(int packageId, AlertType type, DateTime alertDate)
- Future<List<AlertLog>> getByPackage(int packageId)

## 6. Batas tanggung jawab

- UI: menampilkan data dan meneruskan aksi pengguna ke Provider.
- Provider: mengelola state layar, memanggil Service/Repository sesuai kontrak, dan memberi state ke UI.
- Service: menjalankan aturan bisnis, klasifikasi, planner, notifikasi, dan integrasi Android/Firebase.
- Repository: query, transaksi, validasi integritas data, dan konversi Model ↔ SQLite.
- DbHelper: membuka database, membuat skema, mengaktifkan foreign keys, dan migrasi. Fitur anggota tidak boleh mengubah DbHelper.
- Model: bentuk data bersama. Anggota tidak boleh menambah/mengganti field sendiri.

## 7. Aturan implementasi wajib

1. Jangan mengubah kontrak secara sepihak. Ajukan perubahan sebagai PR khusus dan sertakan alasan serta dampaknya pada semua fitur.
2. Jangan membuat tabel, kolom, enum, model, atau repository kedua untuk konsep yang sudah tersedia.
3. Jangan memanggil DbHelper atau SQL langsung dari UI, Provider, atau Service.
4. Jangan mengirim Map database ke UI. Gunakan model.
5. Operasi yang mengubah paket aktif harus berupa transaksi: nonaktifkan paket lain milik user, lalu aktifkan target.
6. Penghapusan paket menghapus kategori, record, rule, alokasi, pengaturan batas, dan alert terkait melalui cascade.
7. Penggantian alokasi harus transaksional. Hapus alokasi lama lalu simpan alokasi baru dalam satu transaksi.
8. Setiap anggota membuat mock/fake repository atau memakai implementasi in-memory yang mengikuti interface yang sama. Jangan mengubah bentuk interface untuk memudahkan satu fitur.
9. Semua perubahan skema setelah v1 harus menaikkan database version dan memiliki migrasi `onUpgrade`. Jangan menghapus database pengguna sebagai solusi migrasi.
10. Gunakan minSdk 29 dan applicationId `com.datawise.datawise`. Jangan menambahkan QUERY_ALL_PACKAGES. Permission Usage Access tetap memakai `PACKAGE_USAGE_STATS`.

## 8. Hal yang harus diselaraskan di kode saat implementasi kontrak

Kerangka saat ini belum sepenuhnya mengikuti dokumen ini. `db_helper.dart` masih memiliki skema lama dengan tabel `data_packages`, `usage_records`, `alert_logs`, dan `app_settings`. Repository in-memory dan interface juga belum memiliki repository kategori, rule, alokasi, dan batas data. `SettingsRepository` saat ini belum menerima user_id. Anggota tidak boleh mulai membuat implementasi final sebelum penyesuaian kontrak kode selesai dan lolos review.

Dokumen ini membekukan bentuk target. Implementasi kode harus diselaraskan dalam satu pekerjaan fondasi oleh arsitek, lalu digabung ke develop. Setelah itu, anggota membuat fitur berdasarkan interface ini.

## 9. Checklist sebelum fitur dimulai

- [ ] Arsitek memperbarui DbHelper menjadi delapan tabel sesuai skema ini.
- [ ] Arsitek membuat seluruh model dan enum sesuai field di atas.
- [ ] Arsitek memperbarui seluruh interface repository.
- [ ] Implementasi in-memory mengikuti seluruh interface repository.
- [ ] Test repository untuk CRUD, foreign key, paket aktif tunggal, manual override, dan total alokasi tersedia.
- [ ] `flutter analyze` dan `flutter test` lulus.
- [ ] Dokumen ERD dan README menunjuk ke kontrak ini.
- [ ] Kontrak disepakati tim sebelum anggota mulai implementasi fitur.


## 10. SQL DDL acuan

SQL berikut adalah definisi tabel v1. Jalankan seluruh statement dalam urutan ini. Foreign key wajib aktif pada setiap koneksi SQLite.

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE data_packages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  operator TEXT NOT NULL,
  total_bytes INTEGER NOT NULL CHECK (total_bytes > 0),
  initial_used_bytes INTEGER NOT NULL DEFAULT 0 CHECK (initial_used_bytes >= 0),
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  price INTEGER CHECK (price IS NULL OR price >= 0),
  is_active INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (end_date > start_date)
);

CREATE INDEX idx_data_packages_user_active
  ON data_packages(user_id, is_active);

CREATE UNIQUE INDEX idx_one_active_package_per_user
  ON data_packages(user_id) WHERE is_active = 1;

CREATE TABLE quota_categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  category_type TEXT NOT NULL
    CHECK (category_type IN ('main', 'night', 'social', 'app', 'custom')),
  quota_bytes INTEGER NOT NULL CHECK (quota_bytes > 0),
  start_minute INTEGER CHECK (start_minute IS NULL OR start_minute BETWEEN 0 AND 1439),
  end_minute INTEGER CHECK (end_minute IS NULL OR end_minute BETWEEN 0 AND 1439),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(package_id, name)
);

CREATE UNIQUE INDEX idx_one_main_category_per_package
  ON quota_categories(package_id) WHERE category_type = 'main';

CREATE INDEX idx_quota_categories_package
  ON quota_categories(package_id);

CREATE TABLE usage_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
  record_date TEXT NOT NULL,
  used_bytes INTEGER NOT NULL CHECK (used_bytes >= 0),
  source TEXT NOT NULL CHECK (source IN ('auto', 'manual')),
  updated_at INTEGER NOT NULL,
  UNIQUE(package_id, record_date, source)
);

CREATE INDEX idx_usage_records_package_date
  ON usage_records(package_id, record_date);

CREATE TABLE classification_rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
  category_id INTEGER NOT NULL REFERENCES quota_categories(id) ON DELETE CASCADE,
  app_package_name TEXT NOT NULL,
  start_minute INTEGER CHECK (start_minute IS NULL OR start_minute BETWEEN 0 AND 1439),
  end_minute INTEGER CHECK (end_minute IS NULL OR end_minute BETWEEN 0 AND 1439),
  priority INTEGER NOT NULL DEFAULT 100,
  is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_classification_rules_package_priority
  ON classification_rules(package_id, is_enabled, priority, id);

CREATE TABLE usage_allocations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usage_record_id INTEGER NOT NULL REFERENCES usage_records(id) ON DELETE CASCADE,
  category_id INTEGER NOT NULL REFERENCES quota_categories(id) ON DELETE CASCADE,
  app_package_name TEXT NOT NULL DEFAULT '',
  used_bytes INTEGER NOT NULL CHECK (used_bytes >= 0),
  UNIQUE(usage_record_id, category_id, app_package_name)
);

CREATE INDEX idx_usage_allocations_record
  ON usage_allocations(usage_record_id);

CREATE INDEX idx_usage_allocations_category
  ON usage_allocations(category_id);

CREATE TABLE data_limit_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  package_id INTEGER NOT NULL UNIQUE REFERENCES data_packages(id) ON DELETE CASCADE,
  daily_warning_percent INTEGER NOT NULL DEFAULT 100 CHECK (daily_warning_percent > 0),
  quota_warning_percent INTEGER NOT NULL DEFAULT 10 CHECK (quota_warning_percent BETWEEN 1 AND 100),
  is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
  updated_at INTEGER NOT NULL
);

CREATE TABLE user_settings (
  user_id TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY(user_id, key)
);

CREATE TABLE alert_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  package_id INTEGER NOT NULL REFERENCES data_packages(id) ON DELETE CASCADE,
  alert_type TEXT NOT NULL
    CHECK (alert_type IN ('daily80', 'daily100', 'dailyOver', 'quota10', 'expiring1d')),
  alert_date TEXT NOT NULL,
  sent_at INTEGER NOT NULL,
  UNIQUE(package_id, alert_type, alert_date)
);

CREATE INDEX idx_alert_logs_package_date
  ON alert_logs(package_id, alert_date);
```

Catatan implementasi:
- SQLite tidak dapat menegakkan semua aturan lintas tabel di atas dengan CHECK biasa. Repository/service wajib memvalidasi bahwa kategori dan rule benar-benar milik paket yang sama, jumlah kuota kategori sama dengan total paket, kategori main tersedia, dan jumlah alokasi tidak melebihi record.
- Saat membuat paket, buat paket dan kategori main dalam satu transaksi. Saat mengubah kuota kategori, validasi total kuota dalam satu transaksi.
- Partial unique index memastikan maksimal satu paket aktif per user dan satu kategori main per paket. Aktifkan foreign keys melalui `onConfigure`.
- Database v1 masih tahap pengembangan. Jika sudah ada instalasi pengguna, perubahan skema harus memakai migrasi `onUpgrade`, bukan menghapus database.
