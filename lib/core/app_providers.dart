
 // MILIK ARSITEK. Pendaftaran Repository, Service, dan Provider.
// Integrasi SQLite Settings dan ThemeProvider untuk Anggota A.

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'theme_provider.dart';

import '../features/auth/auth_provider.dart';
import '../features/dashboard/dashboard_provider.dart';
import '../features/package/package_provider.dart';
import '../features/usage_monitor/usage_provider.dart';

import '../repositories/repositories.dart';
import '../repositories/sqflite_settings_repository.dart';

import '../services/alert_service.dart';
import '../services/auth_service.dart';
import '../services/usage_service.dart';

List<SingleChildWidget> buildAppProviders() {
  // --- Repository ---
  final packageRepo = InMemoryPackageRepository();
  final UsageRepository usageRepo = InMemoryUsageRepository(packageRepo);
  final AlertRepository alertRepo = InMemoryAlertRepository();

  // Penyimpanan pengaturan menggunakan SQLite.
  final SettingsRepository settingsRepo =
      SqfliteSettingsRepository();

  // --- Service ---
  final AuthService authService = FirebaseAuthService();
  final UsageService usageService = UsageServiceImpl(usageRepo, settingsRepo);
  final AlertService alertService = AlertServiceImpl(alertRepo, settingsRepo);

  return [
    // --- Repository Provider ---
    Provider<PackageRepository>.value(value: packageRepo),
    Provider<UsageRepository>.value(value: usageRepo),
    Provider<AlertRepository>.value(value: alertRepo),
    Provider<SettingsRepository>.value(value: settingsRepo),

    // --- Service Provider ---
    Provider<AuthService>.value(value: authService),
    Provider<UsageService>.value(value: usageService),
    Provider<AlertService>.value(value: alertService),

    // --- ChangeNotifier Provider ---
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(authService),
    ),
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(settingsRepo),
    ),
    ChangeNotifierProvider<PackageProvider>(
      create: (_) => PackageProvider(packageRepo),
    ),
    ChangeNotifierProvider<UsageProvider>(
      create: (_) => UsageProvider(usageService, usageRepo, packageRepo),
    ),
    ChangeNotifierProvider<DashboardProvider>(
      create: (_) => DashboardProvider(
        packageRepo,
        usageRepo,
        usageService,
        alertService,
      ),
    ),
  ];
}
