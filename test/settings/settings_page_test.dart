import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:datawise/core/theme_provider.dart';
import 'package:datawise/features/auth/auth_provider.dart';
import 'package:datawise/features/settings/settings_page.dart';
import 'package:datawise/features/settings/settings_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/data_export_service.dart';
import 'package:datawise/services/usage_service.dart';

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);

  AppUser? _user;
  int logoutCalls = 0;

  @override
  AppUser? get currentUser => _user;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> logout() async {
    logoutCalls++;
    _user = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  int calls = 0;
  Object? error;

  @override
  Future<DataExportResult> exportAndShare(
    String userId, {
    DateTime? now,
  }) async {
    calls++;

    final failure = error;
    if (failure != null) throw failure;

    return DataExportResult(
      file: File('backup.json'),
      packageCount: 1,
      usageRecordCount: 2,
      totalRows: 9,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late InMemorySettingsRepository repository;
  late _FakeAuth auth;
  late _FakeUsageService usageService;
  late _FakeExportService exportService;
  late ThemeProvider themeProvider;

  setUp(() async {
    repository = InMemorySettingsRepository();
    await repository.upsert(
      UserSetting(
        userId: 'u1',
        themeMode: 'LIGHT',
        paletteKey: 'TEAL',
        notificationsEnabled: true,
        timezoneId: 'Asia/Jakarta',
        updatedAt: DateTime(2026, 11, 25, 8),
      ),
    );

    auth = _FakeAuth(const AppUser(uid: 'u1', email: 'mawan@example.com'));
    usageService = _FakeUsageService();
    exportService = _FakeExportService();
    themeProvider = ThemeProvider(repository);
    await themeProvider.loadForUser('u1');
  });

  Widget buildPage() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) =>
              SettingsProvider(repository, usageService, exportService),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsPage())),
    );
  }

  // Halaman Pengaturan lebih panjang dari viewport bawaan test; layar
  // diperbesar agar seluruh tile ikut dibangun.
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
  }

  testWidgets('menampilkan profil, tema, izin, dan riwayat notifikasi', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('mawan@example.com'), findsOneWidget);
    expect(find.textContaining('UID: u1'), findsOneWidget);

    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text('Palet Warna'), findsOneWidget);
    expect(find.text('Izin akses penggunaan'), findsOneWidget);
    expect(find.text('Riwayat Notifikasi'), findsOneWidget);
    expect(find.text('Ekspor & Backup Data'), findsOneWidget);
    expect(find.text('Keluar dari Akun'), findsOneWidget);
  });

  testWidgets('mengubah Dark Mode memakai ThemeProvider', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Dark Mode'));
    await tester.pumpAndSettle();

    expect(themeProvider.themeMode, ThemeMode.dark);

    // Persistensi tema diuji di theme_provider_test (penyimpanan berjalan
    // pada antrean async milik ThemeProvider).
  });

  testWidgets('preferensi notifikasi tersimpan secara persisten', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Notifikasi aplikasi'),
    );
    await tester.pumpAndSettle();

    expect(repository.items['u1']?.notificationsEnabled, isFalse);
    // Preferensi tema tidak tertimpa.
    expect(repository.items['u1']?.themeMode, 'LIGHT');
    expect(repository.items['u1']?.paletteKey, 'TEAL');
  });

  testWidgets('menampilkan status izin dan membuka pengaturan Android', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.textContaining('Belum diizinkan'), findsOneWidget);

    await tester.tap(find.text('Berikan izin'));
    await tester.pumpAndSettle();

    expect(usageService.openCalls, 1);

    // Setelah izin diberikan dan aplikasi kembali aktif, status diperbarui.
    usageService.granted = true;
    final settings = tester
        .element(find.byType(SettingsPage))
        .read<SettingsProvider>();
    await settings.refreshUsagePermission();
    await tester.pumpAndSettle();

    expect(find.textContaining('Diizinkan.'), findsOneWidget);
    expect(find.text('Berikan izin'), findsNothing);
  });

  testWidgets('ekspor menampilkan hasil yang dilaporkan provider', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Ekspor & Backup Data'));
    await tester.pumpAndSettle();

    expect(exportService.calls, 1);
    expect(find.textContaining('9 baris'), findsOneWidget);
  });

  testWidgets('kegagalan ekspor ditampilkan sebagai pesan galat', (
    tester,
  ) async {
    exportService.error = StateError('disk penuh');

    await pumpPage(tester);

    await tester.tap(find.text('Ekspor & Backup Data'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Gagal mengekspor data'), findsOneWidget);
  });

  testWidgets('logout hanya mengakhiri sesi, data akun tetap ada', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Keluar dari Akun'));
    await tester.pumpAndSettle();

    expect(find.text('Keluar dari akun?'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(auth.logoutCalls, 0);

    await tester.tap(find.text('Keluar dari Akun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();

    expect(auth.logoutCalls, 1);
    expect(find.text('Tidak ada akun'), findsOneWidget);

    // Preferensi dan data akun tidak dihapus oleh logout.
    expect(repository.items['u1'], isNotNull);
  });
}
