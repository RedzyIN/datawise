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
import '../user_repository.dart';

import 'dart:math';

String _newSqlId(String prefix) {
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();

  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$suffix';
}


class SqliteUserRepository implements UserRepository {
  SqliteUserRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;

  final DbHelper h;

  @override
  Future<void> upsert(AppUser user) async {
    final uid = user.uid.trim();
    if (uid.isEmpty) {
      throw const AppException(
        AppException.validation,
        'UID pengguna wajib tersedia.',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'display_name': user.displayName?.trim().isEmpty == true
          ? null
          : user.displayName?.trim(),
      'email': user.email?.trim().isEmpty == true
          ? null
          : user.email?.trim(),
      'updated_at': now,
    };

    final db = await h.database;
    await db.transaction((tx) async {
      final existing = await tx.query(
        'users',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [uid],
        limit: 1,
      );

      if (existing.isEmpty) {
        await tx.insert('users', {
          'id': uid,
          ...values,
          'created_at': now,
        });
      } else {
        await tx.update(
          'users',
          values,
          where: 'id = ?',
          whereArgs: [uid],
        );
      }
    });
  }

  @override
  Future<AppUser?> getById(String uid) async {
    if (uid.trim().isEmpty) return null;

    final rows = await (await h.database).query(
      'users',
      where: 'id = ?',
      whereArgs: [uid],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return AppUser(
      uid: rows.first['id'] as String,
      displayName: rows.first['display_name'] as String?,
      email: rows.first['email'] as String?,
    );
  }
}

class SqlitePackageRepository implements PackageRepository {
  SqlitePackageRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;

  final DbHelper h;

  void _validatePackage(DataPackage package) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    final endDateOnly = DateTime(
      package.endDate.year,
      package.endDate.month,
      package.endDate.day,
    );

    if (package.userId.trim().isEmpty ||
        package.packageName.trim().isEmpty ||
        package.advertisedTotalQuotaBytes <= 0 ||
        package.endDate.isBefore(package.startDate) ||
        (package.status == PackageStatus.active &&
            endDateOnly.isBefore(todayOnly))) {
      throw const AppException(
        AppException.validation,
        'Data paket tidak valid atau masa aktif paket sudah berakhir.',
      );
    }
  }

  @override
  Future<String> add(DataPackage package) async {
    _validatePackage(package);

    final db = await h.database;

    return db.transaction((tx) async {
      final id = package.id ?? _newSqlId('pkg');

      final storedPackage = package.copyWith(
        id: id,
        packageName: package.packageName.trim(),
        operatorName: package.operatorName?.trim().isEmpty == true
            ? null
            : package.operatorName?.trim(),
      );

      if (storedPackage.status == PackageStatus.active) {
        await tx.update(
          'data_packages',
          {'status': 'INACTIVE'},
          where: 'user_id = ? AND status = ?',
          whereArgs: [storedPackage.userId, 'ACTIVE'],
        );
      }

      await tx.insert('data_packages', storedPackage.toMap());

      final mainCategory = QuotaCategory(
        id: _newSqlId('cat'),
        packageId: id,
        categoryName: 'Kuota Utama',
        categoryType: QuotaCategoryType.main,
        capacityBytes: storedPackage.advertisedTotalQuotaBytes,
        isEnabled: true,
        createdAt: storedPackage.createdAt,
      );

      await tx.insert('quota_categories', mainCategory.toMap());

      return id;
    });
  }

  @override
  Future<void> update(DataPackage package) async {
    _validatePackage(package);

    final id = package.id;

    if (id == null) {
      throw const AppException(
        AppException.validation,
        'ID paket wajib tersedia.',
      );
    }

    final db = await h.database;

    await db.transaction((tx) async {
      final packageRows = await tx.query(
        'data_packages',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (packageRows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Paket tidak ditemukan.',
        );
      }

      final oldPackage = DataPackage.fromMap(packageRows.first);

      if (oldPackage.userId != package.userId) {
        throw const AppException(
          AppException.validation,
          'Pemilik paket tidak boleh diubah.',
        );
      }

      final mainRows = await tx.query(
        'quota_categories',
        where: 'package_id = ? AND category_type = ?',
        whereArgs: [id, 'MAIN'],
      );

      if (mainRows.length != 1) {
        throw const AppException(
          AppException.validation,
          'Paket harus memiliki tepat satu kategori utama.',
        );
      }

      final otherRows = await tx.rawQuery(
        '''
        SELECT COALESCE(SUM(capacity_bytes), 0) AS total
        FROM quota_categories
        WHERE package_id = ? AND category_type != ?
        ''',
        [id, 'MAIN'],
      );

      final otherBytes = otherRows.first['total'] as int;
      final newTotal = package.advertisedTotalQuotaBytes;

      if (newTotal <= otherBytes) {
        throw const AppException(
          AppException.validation,
          'Total kuota tidak cukup untuk menampung kategori tambahan.',
        );
      }

      final newMainBytes = newTotal - otherBytes;
      final mainId = mainRows.first['id'] as String;

      if (package.status == PackageStatus.active) {
        await tx.update(
          'data_packages',
          {'status': 'INACTIVE'},
          where: 'user_id = ? AND id != ? AND status = ?',
          whereArgs: [package.userId, id, 'ACTIVE'],
        );
      }

      final storedPackage = package.copyWith(
        packageName: package.packageName.trim(),
        operatorName: package.operatorName?.trim().isEmpty == true
            ? null
            : package.operatorName?.trim(),
      );

      final packageMap = storedPackage.toMap();

      if (newTotal >= oldPackage.advertisedTotalQuotaBytes) {
        // Kuota naik. Perbarui paket dahulu agar trigger menerima
        // kenaikan kapasitas kategori MAIN.
        await tx.update(
          'data_packages',
          packageMap,
          where: 'id = ?',
          whereArgs: [id],
        );

        await tx.update(
          'quota_categories',
          {'capacity_bytes': newMainBytes},
          where: 'id = ?',
          whereArgs: [mainId],
        );
      } else {
        // Kuota turun. Kurangi MAIN dahulu agar jumlah kategori
        // tidak melebihi kuota paket yang baru.
        await tx.update(
          'quota_categories',
          {'capacity_bytes': newMainBytes},
          where: 'id = ?',
          whereArgs: [mainId],
        );

        await tx.update(
          'data_packages',
          packageMap,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<void> delete(String packageId) async {
    final db = await h.database;

    await db.transaction((tx) async {
      final rows = await tx.query(
        'data_packages',
        where: 'id = ?',
        whereArgs: [packageId],
      );

      if (rows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Paket tidak ditemukan.',
        );
      }

      // Hapus data yang memiliki foreign key RESTRICT terlebih dahulu.
      await tx.delete(
        'alert_logs',
        where: 'package_id = ?',
        whereArgs: [packageId],
      );

      await tx.delete(
        'usage_allocations',
        where: 'package_id = ?',
        whereArgs: [packageId],
      );

      await tx.delete(
        'classification_rules',
        where: '''
          quota_category_id IN (
            SELECT id FROM quota_categories WHERE package_id = ?
          )
        ''',
        whereArgs: [packageId],
      );

      // Data kategori, usage record, dan data limit yang memiliki
      // ON DELETE CASCADE akan mengikuti penghapusan paket.
      await tx.delete('data_packages', where: 'id = ?', whereArgs: [packageId]);
    });
  }

  @override
  Future<DataPackage?> getById(String packageId) async {
    final rows = await (await h.database).query(
      'data_packages',
      where: 'id = ?',
      whereArgs: [packageId],
    );

    return rows.isEmpty ? null : DataPackage.fromMap(rows.first);
  }

  @override
  Future<DataPackage?> getActive(String userId) async {
    final rows = await (await h.database).query(
      'data_packages',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'ACTIVE'],
      limit: 1,
    );

    return rows.isEmpty ? null : DataPackage.fromMap(rows.first);
  }

  @override
  Future<List<DataPackage>> getAll(String userId) async {
    final rows = await (await h.database).query(
      'data_packages',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC, id DESC',
    );

    return rows.map(DataPackage.fromMap).toList();
  }

  @override
  Future<void> setActive(String userId, String packageId) async {
    final db = await h.database;

    await db.transaction((tx) async {
      final rows = await tx.query(
        'data_packages',
        where: 'id = ? AND user_id = ?',
        whereArgs: [packageId, userId],
      );

      if (rows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Paket tidak ditemukan.',
        );
      }

      final package = DataPackage.fromMap(rows.first);

      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final endDateOnly = DateTime(
        package.endDate.year,
        package.endDate.month,
        package.endDate.day,
      );

      if (package.status == PackageStatus.archived ||
          package.status == PackageStatus.expired ||
          endDateOnly.isBefore(todayOnly)) {
        throw const AppException(
          AppException.validation,
          'Paket yang kedaluwarsa atau diarsipkan tidak dapat diaktifkan.',
        );
      }

      await tx.update(
        'data_packages',
        {'status': 'INACTIVE'},
        where: 'user_id = ? AND status = ?',
        whereArgs: [userId, 'ACTIVE'],
      );

      await tx.update(
        'data_packages',
        {'status': 'ACTIVE'},
        where: 'id = ? AND user_id = ?',
        whereArgs: [packageId, userId],
      );
    });
  }
}

class SqliteQuotaCategoryRepository implements QuotaCategoryRepository {
  SqliteQuotaCategoryRepository([DbHelper? helper])
    : h = helper ?? DbHelper.instance;

  final DbHelper h;

  void _validate(QuotaCategory category) {
    if (category.categoryName.trim().isEmpty ||
        category.capacityBytes <= 0 ||
        (category.validFrom != null &&
            category.validUntil != null &&
            category.validUntil!.isBefore(category.validFrom!))) {
      throw const AppException(
        AppException.validation,
        'Data kategori tidak valid.',
      );
    }
  }

  @override
  Future<String> add(QuotaCategory category) async {
    _validate(category);

    if (category.categoryType == QuotaCategoryType.main) {
      throw const AppException(
        AppException.validation,
        'Kategori utama dibuat otomatis bersama paket.',
      );
    }

    final db = await h.database;
    final categoryId = category.id ?? _newSqlId('cat');

    await db.transaction((tx) async {
      final packageRows = await tx.query(
        'data_packages',
        where: 'id = ?',
        whereArgs: [category.packageId],
      );

      if (packageRows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Paket tidak ditemukan.',
        );
      }

      final mainRows = await tx.query(
        'quota_categories',
        where: "package_id = ? AND category_type = 'MAIN'",
        whereArgs: [category.packageId],
      );

      if (mainRows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Kategori utama paket tidak ditemukan.',
        );
      }

      final main = QuotaCategory.fromMap(mainRows.first);
      final remainingMain = main.capacityBytes - category.capacityBytes;

      if (remainingMain <= 0) {
        throw const AppException(
          AppException.validation,
          'Sisa kuota utama tidak mencukupi.',
        );
      }

      await tx.update(
        'quota_categories',
        {'capacity_bytes': remainingMain},
        where: 'id = ?',
        whereArgs: [main.id],
      );

      await tx.insert('quota_categories', {
        ...category.toMap(),
        'id': categoryId,
      });
    });

    return categoryId;
  }

  @override
  Future<void> update(QuotaCategory category) async {
    _validate(category);

    if (category.id == null) {
      throw const AppException(
        AppException.validation,
        'ID kategori wajib tersedia.',
      );
    }

    final db = await h.database;

    await db.transaction((tx) async {
      final oldRows = await tx.query(
        'quota_categories',
        where: 'id = ?',
        whereArgs: [category.id],
      );

      if (oldRows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Kategori tidak ditemukan.',
        );
      }

      final old = QuotaCategory.fromMap(oldRows.first);

      if (old.packageId != category.packageId) {
        throw const AppException(
          AppException.validation,
          'Kategori tidak boleh dipindahkan ke paket lain.',
        );
      }

      if (old.categoryType != category.categoryType) {
        throw const AppException(
          AppException.validation,
          'Jenis kategori tidak boleh diubah.',
        );
      }

      if (old.categoryType == QuotaCategoryType.main) {
        throw const AppException(
          AppException.validation,
          'Kuota kategori utama diatur otomatis.',
        );
      }

      final mainRows = await tx.query(
        'quota_categories',
        where: "package_id = ? AND category_type = 'MAIN'",
        whereArgs: [category.packageId],
      );

      if (mainRows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Kategori utama tidak ditemukan.',
        );
      }

      final main = QuotaCategory.fromMap(mainRows.first);

      final nextMainCapacity =
          main.capacityBytes + old.capacityBytes - category.capacityBytes;

      if (nextMainCapacity <= 0) {
        throw const AppException(
          AppException.validation,
          'Kuota utama harus lebih dari nol.',
        );
      }

      final categoryMap = category.toMap();

      if (category.capacityBytes > old.capacityBytes) {
        // Kuota kategori bertambah. Kurangi MAIN terlebih dahulu.
        await tx.update(
          'quota_categories',
          {'capacity_bytes': nextMainCapacity},
          where: 'id = ?',
          whereArgs: [main.id],
        );

        await tx.update(
          'quota_categories',
          categoryMap,
          where: 'id = ?',
          whereArgs: [category.id],
        );
      } else {
        // Kuota kategori berkurang. Perbarui kategori terlebih dahulu.
        await tx.update(
          'quota_categories',
          categoryMap,
          where: 'id = ?',
          whereArgs: [category.id],
        );

        await tx.update(
          'quota_categories',
          {'capacity_bytes': nextMainCapacity},
          where: 'id = ?',
          whereArgs: [main.id],
        );
      }
    });
  }

  @override
  Future<void> delete(String categoryId) async {
    final db = await h.database;

    await db.transaction((tx) async {
      final rows = await tx.query(
        'quota_categories',
        where: 'id = ?',
        whereArgs: [categoryId],
      );

      if (rows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Kategori tidak ditemukan.',
        );
      }

      final category = QuotaCategory.fromMap(rows.first);

      if (category.categoryType == QuotaCategoryType.main) {
        throw const AppException(
          AppException.validation,
          'Kategori utama tidak boleh dihapus.',
        );
      }

      final ruleReferences = await tx.query(
        'classification_rules',
        columns: ['id'],
        where: 'quota_category_id = ?',
        whereArgs: [categoryId],
        limit: 1,
      );

      final allocationReferences = await tx.query(
        'usage_allocations',
        columns: ['id'],
        where: 'quota_category_id = ?',
        whereArgs: [categoryId],
        limit: 1,
      );

      if (ruleReferences.isNotEmpty || allocationReferences.isNotEmpty) {
        throw const AppException(
          AppException.validation,
          'Kategori masih digunakan oleh aturan klasifikasi atau alokasi penggunaan.',
        );
      }

      final mainRows = await tx.query(
        'quota_categories',
        where: "package_id = ? AND category_type = 'MAIN'",
        whereArgs: [category.packageId],
      );

      if (mainRows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Kategori utama tidak ditemukan.',
        );
      }

      final main = QuotaCategory.fromMap(mainRows.first);

      await tx.delete(
        'quota_categories',
        where: 'id = ?',
        whereArgs: [categoryId],
      );

      await tx.update(
        'quota_categories',
        {'capacity_bytes': main.capacityBytes + category.capacityBytes},
        where: 'id = ?',
        whereArgs: [main.id],
      );
    });
  }

  @override
  Future<QuotaCategory?> getById(String id) async {
    final rows = await (await h.database).query(
      'quota_categories',
      where: 'id = ?',
      whereArgs: [id],
    );

    return rows.isEmpty ? null : QuotaCategory.fromMap(rows.first);
  }

  @override
  Future<List<QuotaCategory>> getByPackage(String packageId) async {
    final rows = await (await h.database).query(
      'quota_categories',
      where: 'package_id = ?',
      whereArgs: [packageId],
      orderBy: "CASE WHEN category_type = 'MAIN' THEN 0 ELSE 1 END, id",
    );

    return rows.map(QuotaCategory.fromMap).toList();
  }
}

class SqliteClassificationRuleRepository
    implements ClassificationRuleRepository {
  SqliteClassificationRuleRepository([DbHelper? helper])
    : h = helper ?? DbHelper.instance;

  final DbHelper h;

  void _validate(ClassificationRule rule) {
    final appName = rule.appPackageName;

    if (rule.ruleName.trim().isEmpty ||
        (appName != null && appName.trim().isEmpty) ||
        (rule.startMinute != null &&
            (rule.startMinute! < 0 || rule.startMinute! > 1439)) ||
        (rule.endMinute != null &&
            (rule.endMinute! < 0 || rule.endMinute! > 1439)) ||
        ((rule.startMinute == null) != (rule.endMinute == null)) ||
        rule.daysOfWeekMask < 1 ||
        rule.daysOfWeekMask > 127 ||
        rule.priority < 0) {
      throw const AppException(
        AppException.validation,
        'Aturan klasifikasi tidak valid.',
      );
    }
  }

  Future<void> _validateCategory(
    DatabaseExecutor db,
    ClassificationRule rule,
  ) async {
    final rows = await db.query(
      'quota_categories',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [rule.quotaCategoryId],
    );

    if (rows.isEmpty) {
      throw const AppException(
        AppException.notFound,
        'Kategori untuk aturan klasifikasi tidak ditemukan.',
      );
    }
  }

  @override
  Future<String> add(ClassificationRule rule) async {
    _validate(rule);

    final db = await h.database;
    await _validateCategory(db, rule);

    final id = rule.id ?? _newSqlId('rule');

    await db.insert('classification_rules', {...rule.toMap(), 'id': id});

    return id;
  }

  @override
  Future<void> update(ClassificationRule rule) async {
    _validate(rule);

    if (rule.id == null) {
      throw const AppException(
        AppException.validation,
        'ID aturan wajib tersedia.',
      );
    }

    final db = await h.database;

    await _validateCategory(db, rule);

    final result = await db.update(
      'classification_rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );

    if (result == 0) {
      throw const AppException(
        AppException.notFound,
        'Aturan klasifikasi tidak ditemukan.',
      );
    }
  }

  @override
  Future<void> delete(String ruleId) async {
    final result = await (await h.database).delete(
      'classification_rules',
      where: 'id = ?',
      whereArgs: [ruleId],
    );

    if (result == 0) {
      throw const AppException(
        AppException.notFound,
        'Aturan klasifikasi tidak ditemukan.',
      );
    }
  }

  @override
  Future<List<ClassificationRule>> getByPackage(String packageId) async {
    final rows = await (await h.database).rawQuery(
      '''
      SELECT r.*
      FROM classification_rules r
      INNER JOIN quota_categories c
        ON c.id = r.quota_category_id
      WHERE c.package_id = ?
      ORDER BY r.priority ASC, r.created_at ASC
      ''',
      [packageId],
    );

    return rows.map(ClassificationRule.fromMap).toList();
  }
}

class SqliteUsageRepository implements UsageRepository {
  SqliteUsageRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;

  final DbHelper h;

  void _validateRecord(UsageRecord record) {
    if (record.rxBytes < 0 ||
        record.txBytes < 0 ||
        !record.periodEndAt.isAfter(record.periodStartAt)) {
      throw const AppException(
        AppException.validation,
        'Data pemakaian tidak valid.',
      );
    }

    if (record.recordScope == UsageRecordScope.appUsage &&
        (record.appPackageName == null ||
            record.appPackageName!.trim().isEmpty)) {
      throw const AppException(
        AppException.validation,
        'Nama paket aplikasi wajib diisi untuk catatan pemakaian aplikasi.',
      );
    }
  }

  @override
  Future<String> upsertRecord(UsageRecord record) async {
    _validateRecord(record);

    final db = await h.database;

    return db.transaction((txn) async {
      // Pastikan paket tujuan tersedia.
      final packageRows = await txn.query(
        'data_packages',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [record.packageId],
      );

      if (packageRows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Paket tidak ditemukan.',
        );
      }

      // Cari sourceKey secara global, bukan berdasarkan package_id.
      Map<String, Object?>? matchingSourceKey;

      if (record.sourceKey != null) {
        final rows = await txn.query(
          'usage_records',
          where: 'source_key = ?',
          whereArgs: [record.sourceKey],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          matchingSourceKey = rows.first;
        }
      }

      // Source key yang sudah dimiliki paket lain tidak boleh digunakan.
      if (matchingSourceKey != null) {
        final existingPackageId = matchingSourceKey['package_id'] as String;
        final existingSourceId = matchingSourceKey['id'] as String;

        if (existingPackageId != record.packageId) {
          throw const AppException(
            AppException.validation,
            'Source key sudah digunakan oleh paket lain.',
          );
        }

        if (record.id != null && record.id != existingSourceId) {
          throw const AppException(
            AppException.validation,
            'Source key sudah digunakan oleh catatan lain.',
          );
        }
      }

      // Tentukan ID catatan yang akan diperbarui atau dibuat.
      final existingId = record.id ?? matchingSourceKey?['id'] as String?;

      // Jika ID diberikan, pastikan catatan tersebut memang milik paket ini.
      if (existingId != null) {
        final existingRows = await txn.query(
          'usage_records',
          columns: ['package_id'],
          where: 'id = ?',
          whereArgs: [existingId],
          limit: 1,
        );

        if (existingRows.isNotEmpty &&
            existingRows.first['package_id'] != record.packageId) {
          throw const AppException(
            AppException.validation,
            'Catatan pemakaian tidak dapat dipindahkan ke paket lain.',
          );
        }
      }

      final id = existingId ?? _newSqlId('usage');

      final values = {...record.toMap(), 'id': id};

      if (existingId != null) {
        final affectedRows = await txn.update(
          'usage_records',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );

        if (affectedRows == 0) {
          await txn.insert('usage_records', values);
        }
      } else {
        await txn.insert('usage_records', values);
      }

      return id;
    });
  }

  @override
  Future<void> deleteManualRecords(
    String packageId,
    DateTime periodStartAt,
    DateTime periodEndAt,
  ) async {
    if (!periodEndAt.isAfter(periodStartAt)) {
      throw const AppException(
        AppException.validation,
        'Rentang waktu pemakaian tidak valid.',
      );
    }

    await (await h.database).delete(
      'usage_records',
      where: '''
        package_id = ?
        AND source = 'MANUAL'
        AND record_scope = 'MANUAL_TOTAL'
        AND period_start_at >= ?
        AND period_end_at <= ?
      ''',
      whereArgs: [packageId, timeToIso(periodStartAt), timeToIso(periodEndAt)],
    );
  }

  @override
  Future<UsageRecord?> getById(String recordId) async {
    final rows = await (await h.database).query(
      'usage_records',
      where: 'id = ?',
      whereArgs: [recordId],
    );

    return rows.isEmpty ? null : UsageRecord.fromMap(rows.first);
  }

  @override
  Future<List<UsageRecord>> getRecords(String packageId) async {
    final rows = await (await h.database).query(
      'usage_records',
      where: 'package_id = ?',
      whereArgs: [packageId],
      orderBy: 'period_start_at ASC, recorded_at ASC',
    );

    return rows.map(UsageRecord.fromMap).toList();
  }

  @override
  Future<List<UsageRecord>> getRecordsForPeriod(
    String packageId,
    DateTime startAt,
    DateTime endAt,
  ) async {
    if (!endAt.isAfter(startAt)) {
      throw const AppException(
        AppException.validation,
        'Rentang waktu pemakaian tidak valid.',
      );
    }

    final rows = await (await h.database).query(
      'usage_records',
      where: '''
        package_id = ?
        AND period_start_at < ?
        AND period_end_at > ?
      ''',
      whereArgs: [packageId, timeToIso(endAt), timeToIso(startAt)],
      orderBy: 'period_start_at ASC',
    );

    return rows.map(UsageRecord.fromMap).toList();
  }

  @override
  Future<void> replaceAllocations(
    String usageRecordId,
    List<UsageAllocation> allocations,
  ) async {
    final db = await h.database;

    await db.transaction((tx) async {
      final recordRows = await tx.query(
        'usage_records',
        where: 'id = ?',
        whereArgs: [usageRecordId],
      );

      if (recordRows.isEmpty) {
        throw const AppException(
          AppException.notFound,
          'Catatan pemakaian tidak ditemukan.',
        );
      }

      final record = UsageRecord.fromMap(recordRows.first);

      // Alokasi kategori hanya berlaku untuk catatan penggunaan aplikasi.
      if (record.recordScope != UsageRecordScope.appUsage ||
          record.networkType == NetworkType.wifi) {
        throw const AppException(
          AppException.validation,
          'Catatan pemakaian ini tidak dapat memiliki alokasi kategori.',
        );
      }

      final totalAllocated = allocations.fold<int>(
        0,
        (total, allocation) => total + allocation.allocatedBytes,
      );

      if (allocations.any((allocation) => allocation.allocatedBytes < 0) ||
          totalAllocated > record.totalBytes) {
        throw const AppException(
          AppException.validation,
          'Jumlah alokasi tidak valid atau melebihi total pemakaian.',
        );
      }

      for (final allocation in allocations) {
        if (allocation.packageId != record.packageId ||
            allocation.usageRecordId != usageRecordId) {
          throw const AppException(
            AppException.validation,
            'Alokasi tidak sesuai dengan catatan pemakaian.',
          );
        }

        if (allocation.quotaCategoryId != null) {
          final categoryRows = await tx.query(
            'quota_categories',
            columns: ['id'],
            where: 'id = ? AND package_id = ?',
            whereArgs: [allocation.quotaCategoryId, record.packageId],
          );

          if (categoryRows.isEmpty) {
            throw const AppException(
              AppException.validation,
              'Kategori alokasi tidak sesuai dengan paket.',
            );
          }
        }

        if (allocation.classificationRuleId != null) {
          final ruleRows = await tx.query(
            'classification_rules',
            columns: ['id', 'quota_category_id'],
            where: 'id = ?',
            whereArgs: [allocation.classificationRuleId],
          );

          if (ruleRows.isEmpty ||
              ruleRows.first['quota_category_id'] !=
                  allocation.quotaCategoryId) {
            throw const AppException(
              AppException.validation,
              'Aturan klasifikasi tidak sesuai dengan kategori alokasi.',
            );
          }
        }
      }

      await tx.delete(
        'usage_allocations',
        where: 'usage_record_id = ?',
        whereArgs: [usageRecordId],
      );

      for (final allocation in allocations) {
        final id = allocation.id ?? _newSqlId('alloc');

        await tx.insert('usage_allocations', {...allocation.toMap(), 'id': id});
      }
    });
  }

  @override
  Future<List<UsageAllocation>> getAllocations(String usageRecordId) async {
    final rows = await (await h.database).query(
      'usage_allocations',
      where: 'usage_record_id = ?',
      whereArgs: [usageRecordId],
      orderBy: 'created_at ASC',
    );

    return rows.map(UsageAllocation.fromMap).toList();
  }

  @override
  Future<List<UsageAllocation>> getAllocationsByPackage(
    String packageId,
  ) async {
    final rows = await (await h.database).rawQuery(
      '''
      SELECT a.*
      FROM usage_allocations a
      INNER JOIN usage_records u
        ON u.id = a.usage_record_id
      WHERE u.package_id = ?
      ORDER BY a.created_at ASC
      ''',
      [packageId],
    );

    return rows.map(UsageAllocation.fromMap).toList();
  }
}

class SqliteDataLimitRepository implements DataLimitRepository {
  SqliteDataLimitRepository([DbHelper? helper])
    : h = helper ?? DbHelper.instance;

  final DbHelper h;

  @override
  Future<DataLimitSetting?> getByPackage(String packageId) async {
    final rows = await (await h.database).query(
      'data_limit_settings',
      where: 'package_id = ?',
      whereArgs: [packageId],
    );

    return rows.isEmpty ? null : DataLimitSetting.fromMap(rows.first);
  }

  @override
  Future<void> upsert(DataLimitSetting setting) async {
    if ((setting.dailyLimitBytes != null && setting.dailyLimitBytes! <= 0) ||
        setting.warnAtPercent < 1 ||
        setting.warnAtPercent > 100 ||
        setting.limitAtPercent < 1 ||
        setting.limitAtPercent > 100 ||
        setting.warnAtPercent > setting.limitAtPercent) {
      throw const AppException(
        AppException.validation,
        'Pengaturan batas pemakaian tidak valid.',
      );
    }

    final db = await h.database;

    final packageRows = await db.query(
      'data_packages',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [setting.packageId],
    );

    if (packageRows.isEmpty) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    await db.insert(
      'data_limit_settings',
      setting.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String packageId) async {
    await (await h.database).delete(
      'data_limit_settings',
      where: 'package_id = ?',
      whereArgs: [packageId],
    );
  }
}

class SqliteAlertRepository implements AlertRepository {
  SqliteAlertRepository([DbHelper? helper]) : h = helper ?? DbHelper.instance;

  final DbHelper h;

  @override
  Future<String> add(AlertLog alert) async {
    if (alert.packageId.trim().isEmpty ||
        alert.alertType.trim().isEmpty ||
        alert.message.trim().isEmpty ||
        alert.dedupeKey.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Data notifikasi tidak valid.',
      );
    }

    final db = await h.database;

    final existingRows = await db.query(
      'alert_logs',
      columns: ['id'],
      where: 'dedupe_key = ?',
      whereArgs: [alert.dedupeKey],
      limit: 1,
    );

    if (existingRows.isNotEmpty) {
      return existingRows.first['id'] as String;
    }

    final id = alert.id ?? _newSqlId('alert');

    await db.insert('alert_logs', {...alert.toMap(), 'id': id});

    return id;
  }

  @override
  Future<bool> existsByDedupeKey(String dedupeKey) async {
    final rows = await (await h.database).query(
      'alert_logs',
      columns: ['id'],
      where: 'dedupe_key = ?',
      whereArgs: [dedupeKey],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  @override
  Future<List<AlertLog>> getByPackage(String packageId) async {
    final rows = await (await h.database).query(
      'alert_logs',
      where: 'package_id = ?',
      whereArgs: [packageId],
      orderBy: 'triggered_at DESC',
    );

    return rows.map(AlertLog.fromMap).toList();
  }

  @override
  Future<void> markRead(String alertId) async {
    final result = await (await h.database).update(
      'alert_logs',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [alertId],
    );

    if (result == 0) {
      throw const AppException(
        AppException.notFound,
        'Notifikasi tidak ditemukan.',
      );
    }
  }

  @override
  Future<void> markAllRead(String packageId) async {
    await (await h.database).update(
      'alert_logs',
      {'is_read': 1},
      where: 'package_id = ? AND is_read = 0',
      whereArgs: [packageId],
    );
  }
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository([DbHelper? helper])
    : h = helper ?? DbHelper.instance;

  final DbHelper h;

  @override
  Future<UserSetting?> getByUserId(String userId) async {
    final rows = await (await h.database).query(
      'user_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    return rows.isEmpty ? null : UserSetting.fromMap(rows.first);
  }

  @override
  Future<void> upsert(UserSetting setting) async {
    if (setting.userId.trim().isEmpty ||
        setting.themeMode.trim().isEmpty ||
        setting.paletteKey.trim().isEmpty ||
        setting.timezoneId.trim().isEmpty) {
      throw const AppException(
        AppException.validation,
        'Pengaturan pengguna tidak valid.',
      );
    }

    await (await h.database).insert(
      'user_settings',
      setting.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String userId) async {
    await (await h.database).delete(
      'user_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
