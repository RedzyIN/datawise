// Regresi: halaman Riwayat wajib memakai header global DATAWISE.
import 'package:datawise/features/alerts/alert_provider.dart';
import 'package:datawise/features/auth/auth_provider.dart';
import 'package:datawise/features/history/history_page.dart';
import 'package:datawise/features/package/package_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);

  final AppUser? _user;

  @override
  AppUser? get currentUser => _user;

  @override
  AuthStatus get status =>
      _user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;

  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AppUser? user, InMemoryPackageRepository packages) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth(user)),
      ChangeNotifierProvider<PackageProvider>(
        create: (_) => PackageProvider(packages),
      ),
      ChangeNotifierProvider<AlertProvider>(
        create: (_) =>
            AlertProvider(InMemoryAlertRepository(packages), packages),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: HistoryPage())),
  );
}

void main() {
  const user = AppUser(uid: 'u1', email: 'kiki@mail.com');

  testWidgets('halaman Riwayat menampilkan header DATAWISE dan judul', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final packages = InMemoryPackageRepository();
    final now = DateTime.now();

    await packages.add(
      DataPackage(
        userId: user.uid,
        packageName: 'Paket A',
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10000000000,
        startDate: dateOnly(now.subtract(const Duration(days: 40))),
        endDate: dateOnly(now.subtract(const Duration(days: 5))),
        status: PackageStatus.expired,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(_app(user, packages));
    await tester.pumpAndSettle();

    expect(find.text('DATAWISE'), findsOneWidget);
    expect(find.text('Riwayat'), findsOneWidget);
    expect(find.text('Riwayat Paket'), findsOneWidget);
    expect(find.text('Paket A'), findsOneWidget);
  });

  testWidgets('header tetap tampil saat riwayat kosong', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(user, InMemoryPackageRepository()));
    await tester.pumpAndSettle();

    expect(find.text('DATAWISE'), findsOneWidget);
    expect(find.text('Belum Ada Riwayat Paket'), findsOneWidget);
  });
}
