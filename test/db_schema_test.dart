import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datawise/core/db_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('database creates all eight contract tables and enables foreign keys', () async {
    final db = await DbHelper.instance.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = rows.map((row) => row['name'] as String).toSet();

    expect(names, containsAll({
      'data_packages',
      'quota_categories',
      'usage_records',
      'classification_rules',
      'usage_allocations',
      'data_limit_settings',
      'user_settings',
      'alert_logs',
    }));

    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.first.values.first, 1);
  });

  test('SQLite prevents two active packages for the same user', () async {
    final db = await DbHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    Future<void> insertPackage(String name) async {
      await db.insert('data_packages', {
        'user_id': 'test-user',
        'name': name,
        'operator': 'Test',
        'total_bytes': 1000,
        'initial_used_bytes': 0,
        'start_date': '2026-11-01',
        'end_date': '2026-12-01',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }

    await insertPackage('Paket A');
    expect(() => insertPackage('Paket B'), throwsA(isA<DatabaseException>()));
  });
}
