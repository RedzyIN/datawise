import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datawise/core/db_helper.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';

void main() {
  late DbHelper helper;
  late SqliteUserRepository users;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    const path = 'datawise_user_repository_test.db';
    await databaseFactory.deleteDatabase(path);
    helper = DbHelper.forTesting(path);
    users = SqliteUserRepository(helper);
  });

  tearDown(() async {
    await helper.close();
  });

  test('profil lokal dapat dibuat dan dibaca berdasarkan UID Firebase', () async {
    await users.upsert(
      const AppUser(
        uid: 'firebase-user-1',
        displayName: 'Pengguna Tes',
        email: 'test@example.com',
      ),
    );

    final saved = await users.getById('firebase-user-1');

    expect(saved?.uid, 'firebase-user-1');
    expect(saved?.displayName, 'Pengguna Tes');
    expect(saved?.email, 'test@example.com');
  });

  test('memperbarui profil tidak menghapus paket milik pengguna', () async {
    await users.upsert(
      const AppUser(uid: 'firebase-user-1', email: 'old@example.com'),
    );

    final packages = SqlitePackageRepository(helper);
    final now = DateTime(2026, 11, 15);
    await packages.add(
      DataPackage(
        userId: 'firebase-user-1',
        packageName: 'Paket Tes',
        advertisedTotalQuotaBytes: 1000000000,
        startDate: DateTime(2026, 11, 15),
        endDate: DateTime(2026, 11, 30),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await users.upsert(
      const AppUser(
        uid: 'firebase-user-1',
        displayName: 'Nama Baru',
        email: 'new@example.com',
      ),
    );

    expect(await packages.getAll('firebase-user-1'), hasLength(1));
    expect((await users.getById('firebase-user-1'))?.email, 'new@example.com');
  });

  test('menolak UID kosong', () async {
    await expectLater(
      users.upsert(const AppUser(uid: ' ')),
      throwsA(isA<AppException>()),
    );
  });

  test('repository in-memory menyimpan profil dengan UID yang sama', () async {
    final memory = InMemoryUserRepository();
    await memory.upsert(
      const AppUser(uid: 'firebase-user-2', email: 'memory@example.com'),
    );

    expect(
      (await memory.getById('firebase-user-2'))?.email,
      'memory@example.com',
    );
  });
}
