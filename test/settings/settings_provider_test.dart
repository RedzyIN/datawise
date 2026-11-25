import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/features/settings/settings_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/data_export_service.dart';
import 'package:datawise/services/usage_service.dart';

class _FakeUsageService implements UsageService {
  bool granted = false;
  int openCalls = 0;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<void> openUsageAccessSettings() async {
    openCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExportService implements DataExportService {
  DataExportResult? result;
  Object? error;
  int calls = 0;
  String? lastUserId;

  @override
  Future<DataExportResult> exportAndShare(
    String userId, {
    DateTime? now,
  }) async {
    calls++;
    lastUserId = userId;

    final failure = error;
    if (failure != null) throw failure;

    return result ??
        DataExportResult(
          file: File('backup.json'),
          packageCount: 0,
          usageRecordCount: 0,
          totalRows: 0,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserSetting _setting({
  required String userId,
  String themeMode = 'LIGHT',
  String paletteKey = 'TEAL',
  bool notificationsEnabled = true,
}) {
  return UserSetting(
    userId: userId,
    themeMode: themeMode,
    paletteKey: paletteKey,
    notificationsEnabled: notificationsEnabled,
    timezoneId: 'Asia/Jakarta',
    updatedAt: DateTime(2026, 11, 25, 8),
  );
}

void main() {
  late InMemorySettingsRepository repository;
  late _FakeUsageService usageService;
  late _FakeExportService exportService;
  late SettingsProvider provider;

  setUp(() {
    repository = InMemorySettingsRepository();
    usageService = _FakeUsageService();
    exportService = _FakeExportService();
    provider = SettingsProvider(repository, usageService, exportService);
  });

  group('preferensi notifikasi', () {
    test('memuat preferensi milik akun aktif', () async {
      await repository.upsert(
        _setting(userId: 'u1', notificationsEnabled: false),
      );

      await provider.loadForUser('u1');

      expect(provider.notificationsEnabled, isFalse);
    });

    test('preferensi tersimpan tanpa menimpa tema dan palet', () async {
      await repository.upsert(
        _setting(userId: 'u1', themeMode: 'DARK', paletteKey: 'RED_ACCENT'),
      );

      await provider.loadForUser('u1');
      await provider.setNotificationsEnabled(false);

      final saved = repository.items['u1']!;

      expect(saved.notificationsEnabled, isFalse);
      expect(saved.themeMode, 'DARK');
      expect(saved.paletteKey, 'RED_ACCENT');
      expect(saved.timezoneId, 'Asia/Jakarta');
    });

    test('perubahan diabaikan saat belum ada akun', () async {
      await provider.loadForUser(null);

      await provider.setNotificationsEnabled(false);

      expect(provider.notificationsEnabled, isTrue);
      expect(repository.items, isEmpty);
    });

    test('preferensi akun lain tidak terbawa', () async {
      await repository.upsert(
        _setting(userId: 'u1', notificationsEnabled: false),
      );
      await repository.upsert(_setting(userId: 'u2'));

      await provider.loadForUser('u1');
      expect(provider.notificationsEnabled, isFalse);

      await provider.loadForUser('u2');
      expect(provider.notificationsEnabled, isTrue);

      await provider.loadForUser(null);
      expect(provider.notificationsEnabled, isTrue);
    });
  });

  group('izin akses penggunaan', () {
    test('mencerminkan status izin Android yang sebenarnya', () async {
      usageService.granted = false;
      await provider.loadForUser('u1');

      expect(provider.usagePermissionGranted, isFalse);

      usageService.granted = true;
      await provider.refreshUsagePermission();

      expect(provider.usagePermissionGranted, isTrue);
    });

    test(
      'tombol izin membuka pengaturan Android lalu memeriksa ulang',
      () async {
        usageService.granted = false;
        await provider.loadForUser('u1');

        await provider.requestUsagePermission();

        // Meski pengguna belum mengubah apa pun, status tetap dibaca ulang.
        expect(usageService.openCalls, 1);
        expect(provider.usagePermissionGranted, isFalse);
      },
    );
  });

  group('ekspor data', () {
    test('status berhasil membawa jumlah baris', () async {
      exportService.result = DataExportResult(
        file: File('backup.json'),
        packageCount: 2,
        usageRecordCount: 5,
        totalRows: 9,
      );

      await provider.loadForUser('u1');

      expect(provider.exportStatus, DataExportStatus.idle);

      await provider.exportData();

      expect(provider.exportStatus, DataExportStatus.success);
      expect(exportService.lastUserId, 'u1');
      expect(provider.exportMessage, contains('9'));
      expect(provider.errorMessage, isNull);
    });

    test('kegagalan ekspor dilaporkan tanpa melempar ke UI', () async {
      exportService.error = StateError('disk penuh');

      await provider.loadForUser('u1');
      await provider.exportData();

      expect(provider.exportStatus, DataExportStatus.failure);
      expect(provider.errorMessage, isNotNull);
      expect(provider.exportMessage, isNull);
    });

    test('ekspor tanpa akun tidak memanggil service', () async {
      await provider.loadForUser(null);

      await provider.exportData();

      expect(exportService.calls, 0);
      expect(provider.exportStatus, DataExportStatus.failure);
      expect(provider.errorMessage, contains('Masuk'));
    });
  });
}
