
import 'package:sqflite/sqflite.dart';

import '../core/db_helper.dart';
import 'settings_repository.dart';

class SqfliteSettingsRepository implements SettingsRepository {
  SqfliteSettingsRepository() : _dbHelper = DbHelper.instance;

  final DbHelper _dbHelper;

  @override
  Future<String?> get(String key) async {
    final db = await _dbHelper.database;

    final result = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isEmpty) return null;

    return result.first['value'] as String?;
  }

  @override
  Future<void> set(String key, String value) async {
    final db = await _dbHelper.database;

    await db.insert(
      'app_settings',
      {
        'key': key,
        'value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
