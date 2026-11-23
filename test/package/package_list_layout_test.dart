// Regresi layout: Daftar Paket tidak boleh overflow pada layar sempit.
import 'package:datawise/core/theme.dart';
import 'package:datawise/features/auth/auth_provider.dart';
import 'package:datawise/features/package/package_list_page.dart';
import 'package:datawise/features/package/package_provider.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  AppUser? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepo implements PackageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPage(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth()),
        ChangeNotifierProvider<PackageProvider>(
          create: (_) => PackageProvider(_FakeRepo()),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: PackageListPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [380.0, 320.0, 360.0]) {
    testWidgets('Daftar Paket tanpa overflow pada lebar $width', (
      tester,
    ) async {
      await _pumpPage(tester, width);
      expect(tester.takeException(), isNull);
    });
  }
}
