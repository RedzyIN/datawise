import 'package:datawise/features/alerts/alert_history_page.dart';
import 'package:datawise/features/alerts/alert_provider.dart';
import 'package:datawise/features/auth/auth_provider.dart';
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AlertProvider provider, AppUser? user) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AlertProvider>.value(value: provider),
      ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth(user)),
    ],
    child: const MaterialApp(home: AlertHistoryPage()),
  );
}

void main() {
  const user = AppUser(uid: 'u1', email: 'kiki@mail.com');

  late InMemoryPackageRepository packages;
  late InMemoryAlertRepository alerts;
  late AlertProvider provider;

  setUp(() {
    packages = InMemoryPackageRepository();
    alerts = InMemoryAlertRepository(packages);
    provider = AlertProvider(alerts, packages);
  });

  Future<String> addPackage(String name) {
    final now = DateTime.now();

    return packages.add(
      DataPackage(
        userId: user.uid,
        packageName: name,
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10000000000,
        startDate: dateOnly(now.subtract(const Duration(days: 3))),
        endDate: dateOnly(now.add(const Duration(days: 20))),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  testWidgets('menampilkan empty state ketika belum ada riwayat', (
    tester,
  ) async {
    await addPackage('Paket A');

    await tester.pumpWidget(_app(provider, user));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat Notifikasi'), findsOneWidget);
    expect(find.text('Belum Ada Riwayat Notifikasi'), findsOneWidget);

    provider.dispose();
  });

  testWidgets('menampilkan pesan, paket, waktu, dan status belum dibaca', (
    tester,
  ) async {
    final packageId = await addPackage('Paket A');

    await alerts.createIfAbsent(
      AlertLog(
        packageId: packageId,
        alertType: alertTypeToDb(AlertType.quota20),
        message: 'Sisa kuota utama Paket A tinggal 15%.',
        observedBytes: 1500000000,
        thresholdBytes: 2000000000,
        dedupeKey: '$packageId:quota20:2026-11-17',
        triggeredAt: DateTime(2026, 11, 17, 9, 15),
        isRead: false,
      ),
    );

    await tester.pumpWidget(_app(provider, user));
    await tester.pumpAndSettle();

    expect(find.text('Sisa kuota utama menipis'), findsOneWidget);
    expect(find.text('Sisa kuota utama Paket A tinggal 15%.'), findsOneWidget);
    expect(find.text('Paket A'), findsOneWidget);
    expect(find.textContaining('17 Nov 2026'), findsOneWidget);
    expect(find.text('Belum dibaca'), findsOneWidget);

    provider.dispose();
  });

  testWidgets('mengetuk alert menandainya sudah dibaca', (tester) async {
    final packageId = await addPackage('Paket A');

    await alerts.createIfAbsent(
      AlertLog(
        packageId: packageId,
        alertType: alertTypeToDb(AlertType.daily100),
        message: 'Target harian tercapai.',
        dedupeKey: '$packageId:daily100:2026-11-17',
        triggeredAt: DateTime(2026, 11, 17, 10),
        isRead: false,
      ),
    );

    await tester.pumpWidget(_app(provider, user));
    await tester.pumpAndSettle();

    expect(find.text('Belum dibaca'), findsOneWidget);

    await tester.tap(find.text('Target harian tercapai.'));
    await tester.pumpAndSettle();

    expect(find.text('Sudah dibaca'), findsOneWidget);
    expect(provider.unreadCount, 0);
    expect((await alerts.getByPackage(packageId)).single.isRead, isTrue);

    provider.dispose();
  });
}
