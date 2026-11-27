import 'package:datawise/core/theme.dart';
import 'package:datawise/features/auth/auth_provider.dart';
import 'package:datawise/features/package/package_form_page.dart';
import 'package:datawise/features/package/package_provider.dart';
import 'package:datawise/features/package/quota_category_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);

  final AppUser _user;

  @override
  AppUser? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpForm(WidgetTester tester) async {
  // Lebar cukup lebar agar font pengganti flutter_test tidak memicu
  // overflow pada baris tombol kategori yang sudah ada.
  tester.view.physicalSize = const Size(600, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final packages = InMemoryPackageRepository();
  final categories = InMemoryQuotaCategoryRepository(packages);
  final usage = InMemoryUsageRepository(packages, categories);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) =>
              _FakeAuth(const AppUser(uid: 'u1', email: 'tes@example.com')),
        ),
        ChangeNotifierProvider<PackageProvider>(
          create: (_) => PackageProvider(packages, usageRepo: usage),
        ),
        ChangeNotifierProvider<QuotaCategoryProvider>(
          create: (_) => QuotaCategoryProvider(categories),
        ),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const PackageFormPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('form menampilkan input dan menghitung sisa kuota awal', (
    tester,
  ) async {
    await _pumpForm(tester);

    expect(find.text('Kuota Sudah Terpakai'), findsOneWidget);
    expect(find.textContaining('Isi 0 jika paket masih baru'), findsOneWidget);
    expect(find.text('Sisa kuota awal'), findsOneWidget);

    // Kolom 0 nama paket, 1 total kuota, 2 kuota sudah terpakai.
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '7');
    await tester.enterText(fields.at(2), '3.5');
    await tester.pump();

    // 7 GB - 3,5 GB = 3,5 GB dihitung langsung di form.
    expect(find.text('3,50 GB'), findsOneWidget);
  });

  testWidgets('pemakaian awal melebihi total kuota ditolak', (tester) async {
    await _pumpForm(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Paket Internet');
    await tester.enterText(fields.at(1), '7');
    await tester.enterText(fields.at(2), '10');
    await tester.pump();

    await tester.ensureVisible(find.text('Simpan Paket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Paket'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('tidak boleh melebihi total kuota'),
      findsOneWidget,
    );
  });
}
