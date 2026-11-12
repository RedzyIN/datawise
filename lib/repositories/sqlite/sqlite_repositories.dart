import 'package:sqflite/sqflite.dart';
import '../../core/db_helper.dart';
import '../../models/models.dart';
import '../alert_repository.dart';
import '../classification_rule_repository.dart';
import '../data_limit_repository.dart';
import '../package_repository.dart';
import '../quota_category_repository.dart';
import '../settings_repository.dart';
import '../usage_repository.dart';

class SqlitePackageRepository implements PackageRepository {
  SqlitePackageRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;
  final DbHelper h;
  void valid(DataPackage p) {
    if (p.userId.trim().isEmpty || p.name.trim().isEmpty || p.operator.trim().isEmpty ||
        p.totalBytes <= 0 || p.initialUsedBytes < 0 || !p.endDate.isAfter(p.startDate)) {
      throw const AppException(AppException.validation, 'Data paket tidak valid.');
    }
  }
  @override Future<int> add(DataPackage p) async {
    valid(p); final db = await h.database;
    return db.transaction((t) async {
      if (p.isActive) await t.update('data_packages', {'is_active': 0}, where: 'user_id = ?', whereArgs: [p.userId]);
      final id = await t.insert('data_packages', p.toMap());
      await t.insert('quota_categories', {'package_id': id, 'name': 'Kuota Utama', 'category_type': 'main',
        'quota_bytes': p.totalBytes, 'created_at': timeToMs(p.createdAt), 'updated_at': timeToMs(p.updatedAt)});
      return id;
    });
  }
  @override Future<void> update(DataPackage p) async {
    valid(p);
    final id = p.id;
    if (id == null) throw const AppException(AppException.validation, 'ID paket wajib tersedia.');
    final db = await h.database;
    await db.transaction((t) async {
      final old = await t.query('data_packages', where: 'id = ?', whereArgs: [id]);
      if (old.isEmpty) throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
      if (old.first['user_id'] != p.userId) {
        throw const AppException(AppException.validation, 'Pemilik paket tidak boleh diubah.');
      }
      final mainRows = await t.query('quota_categories',
          where: "package_id = ? AND category_type = 'main'", whereArgs: [id]);
      if (mainRows.length != 1) {
        throw const AppException(AppException.validation, 'Paket harus memiliki tepat satu kategori utama.');
      }
      final otherRows = await t.rawQuery(
          "SELECT COALESCE(SUM(quota_bytes),0) total FROM quota_categories WHERE package_id = ? AND category_type != 'main'", [id]);
      final otherBytes = otherRows.first['total'] as int;
      final mainBytes = p.totalBytes - otherBytes;
      if (mainBytes <= 0) {
        throw const AppException(AppException.validation, 'Kuota paket tidak cukup untuk kategori tambahan.');
      }
      if (p.isActive) {
        await t.update('data_packages', {'is_active': 0},
            where: 'user_id = ? AND id != ?', whereArgs: [p.userId, id]);
      }
      // Ubah total paket lebih dahulu agar trigger kategori menerima
      // kenaikan atau penurunan kuota utama dalam transaksi yang sama.
      await t.update('data_packages', p.toMap(), where: 'id = ?', whereArgs: [id]);
      await t.update('quota_categories', {
        'quota_bytes': mainBytes,
        'updated_at': timeToMs(p.updatedAt),
      }, where: 'id = ?', whereArgs: [mainRows.first['id']]);
    });
  }
  @override Future<void> delete(int id) async {
    final n = await (await h.database).delete('data_packages', where: 'id = ?', whereArgs: [id]);
    if (n == 0) throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
  }
  @override Future<DataPackage?> getById(int id) async {
    final r = await (await h.database).query('data_packages', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : DataPackage.fromMap(r.first);
  }
  @override Future<DataPackage?> getActive(String uid) async {
    final r = await (await h.database).query('data_packages', where: 'user_id = ? AND is_active = 1', whereArgs: [uid]);
    return r.isEmpty ? null : DataPackage.fromMap(r.first);
  }
  @override Future<List<DataPackage>> getAll(String uid) async {
    final r = await (await h.database).query('data_packages', where: 'user_id = ?', whereArgs: [uid], orderBy: 'created_at DESC, id DESC');
    return r.map(DataPackage.fromMap).toList();
  }
  @override Future<void> setActive(String uid, int id) async {
    final db = await h.database;
    await db.transaction((t) async {
      final r = await t.query('data_packages', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
      if (r.isEmpty) throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
      await t.update('data_packages', {'is_active': 0}, where: 'user_id = ?', whereArgs: [uid]);
      await t.update('data_packages', {'is_active': 1}, where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
    });
  }
}

class SqliteQuotaCategoryRepository implements QuotaCategoryRepository {
  SqliteQuotaCategoryRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;
  final DbHelper h;
  void valid(QuotaCategory c) {
    if (c.name.trim().isEmpty || c.quotaBytes <= 0 ||
        (c.startMinute != null && (c.startMinute! < 0 || c.startMinute! > 1439)) ||
        (c.endMinute != null && (c.endMinute! < 0 || c.endMinute! > 1439)) ||
        ((c.startMinute == null) != (c.endMinute == null))) {
      throw const AppException(AppException.validation, 'Data kategori tidak valid.');
    }
  }
  @override Future<int> add(QuotaCategory c) async {
    valid(c);
    if (c.type == QuotaCategoryType.main) {
      throw const AppException(AppException.validation, 'Kategori utama dibuat otomatis bersama paket.');
    }
    final db = await h.database;
    return db.transaction((t) async {
      final mains = await t.query('quota_categories',
          where: "package_id = ? AND category_type = 'main'", whereArgs: [c.packageId]);
      if (mains.isEmpty) throw const AppException(AppException.validation, 'Kategori utama paket tidak ditemukan.');
      final main = QuotaCategory.fromMap(mains.first);
      if (main.quotaBytes <= c.quotaBytes) throw const AppException(AppException.validation, 'Sisa kuota utama tidak mencukupi.');
      await t.update('quota_categories',
          {'quota_bytes': main.quotaBytes - c.quotaBytes, 'updated_at': timeToMs(c.updatedAt)},
          where: 'id = ?', whereArgs: [main.id]);
      return t.insert('quota_categories', c.toMap());
    });
  }
  @override Future<void> update(QuotaCategory c) async {
    valid(c);
    if (c.id == null) throw const AppException(AppException.validation, 'ID kategori wajib tersedia.');
    final db = await h.database;
    await db.transaction((t) async {
      final oldRows = await t.query('quota_categories', where: 'id = ?', whereArgs: [c.id]);
      if (oldRows.isEmpty) throw const AppException(AppException.notFound, 'Kategori tidak ditemukan.');
      final old = QuotaCategory.fromMap(oldRows.first);
      if (old.packageId != c.packageId) throw const AppException(AppException.validation, 'Kategori tidak boleh dipindahkan ke paket lain.');
      if (old.type != c.type) throw const AppException(AppException.validation, 'Jenis kategori tidak boleh diubah.');
      final mainRows = await t.query('quota_categories',
          where: "package_id = ? AND category_type = 'main'", whereArgs: [c.packageId]);
      if (mainRows.isEmpty) throw const AppException(AppException.validation, 'Kategori utama tidak ditemukan.');
      final main = QuotaCategory.fromMap(mainRows.first);
      if (old.type == QuotaCategoryType.main) {
        final packageRows = await t.query('data_packages', columns: ['total_bytes'],
            where: 'id = ?', whereArgs: [c.packageId]);
        final others = await t.rawQuery("SELECT COALESCE(SUM(quota_bytes),0) total FROM quota_categories WHERE package_id = ? AND category_type != 'main'", [c.packageId]);
        final totalBytes = packageRows.first['total_bytes'] as int;
        final otherBytes = others.first['total'] as int;
        final residual = totalBytes - otherBytes;
        if (residual <= 0) throw const AppException(AppException.validation, 'Kuota utama harus lebih dari nol.');
        await t.update('quota_categories',
            {'quota_bytes': residual, 'updated_at': timeToMs(c.updatedAt)},
            where: 'id = ?', whereArgs: [c.id]);
      } else {
        final nextMain = main.quotaBytes + old.quotaBytes - c.quotaBytes;
        if (nextMain <= 0) throw const AppException(AppException.validation, 'Kuota utama harus lebih dari nol.');
        await t.update('quota_categories',
            {'quota_bytes': nextMain, 'updated_at': timeToMs(c.updatedAt)},
            where: 'id = ?', whereArgs: [main.id]);
        await t.update('quota_categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
      }
    });
  }
  @override Future<void> delete(int id) async {
    final db = await h.database;
    await db.transaction((t) async {
      final r = await t.query('quota_categories', where: 'id = ?', whereArgs: [id]);
      if (r.isEmpty) throw const AppException(AppException.notFound, 'Kategori tidak ditemukan.');
      final category = QuotaCategory.fromMap(r.first);
      if (category.type == QuotaCategoryType.main) throw const AppException(AppException.validation, 'Kategori utama tidak boleh dihapus.');
      final mains = await t.query('quota_categories',
          where: "package_id = ? AND category_type = 'main'", whereArgs: [category.packageId]);
      if (mains.isEmpty) throw const AppException(AppException.validation, 'Kategori utama tidak ditemukan.');
      final main = QuotaCategory.fromMap(mains.first);
      await t.update('quota_categories',
          {'quota_bytes': main.quotaBytes + category.quotaBytes, 'updated_at': timeToMs(DateTime.now())},
          where: 'id = ?', whereArgs: [main.id]);
      await t.delete('quota_categories', where: 'id = ?', whereArgs: [id]);
    });
  }
  @override Future<QuotaCategory?> getById(int id) async {
    final r = await (await h.database).query('quota_categories', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : QuotaCategory.fromMap(r.first);
  }
  @override Future<List<QuotaCategory>> getByPackage(int id) async {
    final r = await (await h.database).query('quota_categories', where: 'package_id = ?', whereArgs: [id], orderBy: "CASE WHEN category_type = 'main' THEN 0 ELSE 1 END, id");
    return r.map(QuotaCategory.fromMap).toList();
  }
}

class SqliteClassificationRuleRepository implements ClassificationRuleRepository {
  SqliteClassificationRuleRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;
  final DbHelper h;
  void valid(ClassificationRule r) {
    if (r.appPackageName.trim().isEmpty ||
        (r.startMinute != null && (r.startMinute! < 0 || r.startMinute! > 1439)) ||
        (r.endMinute != null && (r.endMinute! < 0 || r.endMinute! > 1439)) ||
        ((r.startMinute == null) != (r.endMinute == null))) {
      throw const AppException(AppException.validation, 'Aturan klasifikasi tidak valid.');
    }
  }
  Future<void> samePackage(DatabaseExecutor db, ClassificationRule r) async {
    final rows = await db.query('quota_categories', columns: ['id'], where: 'id = ? AND package_id = ?', whereArgs: [r.categoryId, r.packageId]);
    if (rows.isEmpty) throw const AppException(AppException.validation, 'Kategori tidak sesuai dengan paket aturan.');
  }
  @override Future<int> add(ClassificationRule r) async { valid(r); final db = await h.database; await samePackage(db, r); return db.insert('classification_rules', r.toMap()); }
  @override Future<void> update(ClassificationRule r) async {
    valid(r); if (r.id == null) throw const AppException(AppException.validation, 'ID aturan wajib tersedia.');
    final db = await h.database; await samePackage(db, r);
    final n = await db.update('classification_rules', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
    if (n == 0) throw const AppException(AppException.notFound, 'Aturan tidak ditemukan.');
  }
  @override Future<void> delete(int id) async {
    final n = await (await h.database).delete('classification_rules', where: 'id = ?', whereArgs: [id]);
    if (n == 0) throw const AppException(AppException.notFound, 'Aturan tidak ditemukan.');
  }
  @override Future<List<ClassificationRule>> getByPackage(int id) async {
    final r = await (await h.database).query('classification_rules', where: 'package_id = ?', whereArgs: [id], orderBy: 'priority, id');
    return r.map(ClassificationRule.fromMap).toList();
  }
}

class SqliteUsageRepository implements UsageRepository {
  SqliteUsageRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;
  final DbHelper h;
  @override Future<void> upsertRecord(int id, DateTime date, int bytes, UsageSource source) async {
    if (bytes < 0) throw const AppException(AppException.validation, 'Pemakaian tidak boleh negatif.');
    await (await h.database).insert('usage_records', {'package_id': id, 'record_date': dateToDb(date), 'used_bytes': bytes, 'source': source.name, 'updated_at': timeToMs(DateTime.now())}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  @override Future<void> deleteManual(int id, DateTime date) async {
    await (await h.database).delete('usage_records', where: "package_id = ? AND record_date = ? AND source = 'manual'", whereArgs: [id, dateToDb(date)]);
  }
  @override Future<UsageRecord?> getEffectiveRecord(int id, DateTime date) async {
    final r = await (await h.database).query('usage_records', where: 'package_id = ? AND record_date = ?', whereArgs: [id, dateToDb(date)], orderBy: "CASE WHEN source = 'manual' THEN 0 ELSE 1 END", limit: 1);
    return r.isEmpty ? null : UsageRecord.fromMap(r.first);
  }
  @override Future<List<UsageRecord>> getEffectiveRecords(int id) async {
    final r = await (await h.database).rawQuery("""SELECT u.* FROM usage_records u WHERE u.package_id = ? AND NOT EXISTS (SELECT 1 FROM usage_records m WHERE m.package_id = u.package_id AND m.record_date = u.record_date AND m.source = 'manual' AND u.source = 'auto') ORDER BY u.record_date""", [id]);
    return r.map(UsageRecord.fromMap).toList();
  }
  @override Future<List<UsageRecord>> getRecords(int id) async {
    final r = await (await h.database).query('usage_records', where: 'package_id = ?', whereArgs: [id], orderBy: 'record_date, source');
    return r.map(UsageRecord.fromMap).toList();
  }
  @override Future<int> getUsedBytesOn(int id, DateTime date) async => (await getEffectiveRecord(id, date))?.usedBytes ?? 0;
  @override Future<int> getTotalUsedBytes(int id) async {
    final db = await h.database;
    final p = await db.query('data_packages', columns: ['initial_used_bytes'], where: 'id = ?', whereArgs: [id]);
    if (p.isEmpty) throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    final r = await getEffectiveRecords(id);
    return (p.first['initial_used_bytes'] as int) + r.fold<int>(0, (s, x) => s + x.usedBytes);
  }
  @override Future<Map<DateTime, int>> getDailyUsage(int id) async {
    final r = await getEffectiveRecords(id);
    return {for (final x in r) dateOnly(x.recordDate): x.usedBytes};
  }
  @override Future<void> replaceAllocations(int id, List<UsageAllocation> items) async {
    final db = await h.database;
    await db.transaction((t) async {
      final rows = await t.query('usage_records', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const AppException(AppException.notFound, 'Catatan pemakaian tidak ditemukan.');
      final record = UsageRecord.fromMap(rows.first);
      final total = items.fold<int>(0, (s, a) => s + a.usedBytes);
      final keys = items.map((a) => '${a.categoryId}|${a.appPackageName}').toSet();
      if ((record.source == UsageSource.manual && items.isNotEmpty) || items.any((a) => a.usedBytes < 0) || total > record.usedBytes || keys.length != items.length) throw const AppException(AppException.validation, 'Data alokasi tidak valid.');
      for (final a in items) {
        final c = await t.query('quota_categories', where: 'id = ? AND package_id = ?', whereArgs: [a.categoryId, record.packageId]);
        if (c.isEmpty) throw const AppException(AppException.validation, 'Kategori alokasi tidak sesuai dengan paket.');
      }
      await t.delete('usage_allocations', where: 'usage_record_id = ?', whereArgs: [id]);
      for (final a in items) {
        await t.insert('usage_allocations', {'usage_record_id': id, 'category_id': a.categoryId, 'app_package_name': a.appPackageName, 'used_bytes': a.usedBytes});
      }
    });
  }
  @override Future<List<UsageAllocation>> getAllocations(int id) async {
    final r = await (await h.database).query('usage_allocations', where: 'usage_record_id = ?', whereArgs: [id]);
    return r.map(UsageAllocation.fromMap).toList();
  }
  @override Future<Map<int, int>> getCategoryUsage(int id) async {
    final r = await (await h.database).rawQuery("""SELECT a.category_id, SUM(a.used_bytes) total FROM usage_allocations a JOIN usage_records u ON u.id = a.usage_record_id WHERE u.package_id = ? AND NOT EXISTS (SELECT 1 FROM usage_records m WHERE m.package_id = u.package_id AND m.record_date = u.record_date AND m.source = 'manual' AND u.source = 'auto') GROUP BY a.category_id""", [id]);
    return {for (final x in r) x['category_id'] as int: x['total'] as int};
  }
}

class SqliteDataLimitRepository implements DataLimitRepository {
  SqliteDataLimitRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;
  final DbHelper h;
  @override Future<DataLimitSetting?> getByPackage(int id) async {
    final r = await (await h.database).query('data_limit_settings', where: 'package_id = ?', whereArgs: [id]);
    return r.isEmpty ? null : DataLimitSetting.fromMap(r.first);
  }
  @override Future<void> upsert(DataLimitSetting s) async {
    if (s.dailyWarningPercent <= 0 || s.quotaWarningPercent < 1 || s.quotaWarningPercent > 100) throw const AppException(AppException.validation, 'Pengaturan batas tidak valid.');
    await (await h.database).insert('data_limit_settings', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

class SqliteAlertRepository implements AlertRepository {
  SqliteAlertRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;
  final DbHelper h;
  @override Future<bool> hasBeenSent(int id, AlertType type, DateTime date) async {
    final r = await (await h.database).query('alert_logs', columns: ['id'], where: 'package_id = ? AND alert_type = ? AND alert_date = ?', whereArgs: [id, type.name, dateToDb(date)]);
    return r.isNotEmpty;
  }
  @override Future<void> markSent(int id, AlertType type, DateTime date) async {
    await (await h.database).insert('alert_logs', {'package_id': id, 'alert_type': type.name, 'alert_date': dateToDb(date), 'sent_at': timeToMs(DateTime.now())}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  @override Future<List<AlertLog>> getByPackage(int id) async {
    final r = await (await h.database).query('alert_logs', where: 'package_id = ?', whereArgs: [id], orderBy: 'alert_date DESC, sent_at DESC');
    return r.map(AlertLog.fromMap).toList();
  }
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;
  final DbHelper h;
  @override Future<String?> get(String uid, String key) async {
    final r = await (await h.database).query('user_settings', columns: ['value'], where: 'user_id = ? AND key = ?', whereArgs: [uid, key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }
  @override Future<void> set(String uid, String key, String value) async {
    if (uid.trim().isEmpty || key.trim().isEmpty) throw const AppException(AppException.validation, 'User ID dan key wajib diisi.');
    await (await h.database).insert('user_settings', {'user_id': uid, 'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  @override Future<void> delete(String uid, String key) async {
    await (await h.database).delete('user_settings', where: 'user_id = ? AND key = ?', whereArgs: [uid, key]);
  }
}
