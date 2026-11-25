// MILIK ARSITEK. firebase_options.dart dibuat oleh `flutterfire configure`.
// Integrasi ThemeProvider untuk pengaturan Light Mode dan Dark Mode.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/app_providers.dart';
import 'core/routes.dart';
import 'core/theme.dart';
import 'core/theme_provider.dart';
import 'features/auth/auth_provider.dart';
import 'firebase_options.dart';
import 'services/data_limit_background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const DatawiseApp());

  // Pemeriksaan Data Limit Warning di latar belakang (Android). Dijadwalkan
  // setelah aplikasi tampil agar pembukaan tidak menunggu platform channel
  // WorkManager; `schedule()` juga melakukan inisialisasi dan menelan
  // kegagalannya.
  unawaited(DataLimitBackgroundScheduler.schedule());
}

class DatawiseApp extends StatefulWidget {
  const DatawiseApp({super.key});

  @override
  State<DatawiseApp> createState() => _DatawiseAppState();
}

class _DatawiseAppState extends State<DatawiseApp> {
  late final List<SingleChildWidget> _providers = buildAppProviders();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(providers: _providers, child: const _ThemeModeApp());
  }
}

class _ThemeModeApp extends StatefulWidget {
  const _ThemeModeApp();

  @override
  State<_ThemeModeApp> createState() => _ThemeModeAppState();
}

class _ThemeModeAppState extends State<_ThemeModeApp> {
  String? _lastUid;
  bool _themeSynced = false;

  /// Memuat tema sesuai akun yang sedang login, hanya saat akun berubah.
  void _syncTheme(String? uid) {
    if (_themeSynced && uid == _lastUid) return;

    _themeSynced = true;
    _lastUid = uid;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ThemeProvider>().loadForUser(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        _syncTheme(auth.currentUser?.uid);

        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              title: 'DATAWISE',
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              darkTheme: buildDarkAppTheme(),
              themeMode: themeProvider.themeMode,
              initialRoute: Routes.gate,
              routes: appRoutes,
            );
          },
        );
      },
    );
  }
}
