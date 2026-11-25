// MILIK ARSITEK. Satu-satunya tempat mendaftarkan Repository, Service, dan Provider.

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'theme_provider.dart';

import '../features/alerts/alert_provider.dart';
import '../features/auth/auth_provider.dart';
import '../features/dashboard/dashboard_provider.dart';
import '../features/data_limit/data_limit_provider.dart';
import '../features/package/package_provider.dart';
import '../features/package/quota_category_provider.dart';
import '../features/settings/settings_provider.dart';
import '../features/usage_breakdown/usage_breakdown_provider.dart';
import '../features/usage_monitor/usage_provider.dart';

import '../repositories/repositories.dart';

import '../services/alert_service.dart';
import '../services/alert_simulation.dart';
import '../services/app_usage_sync_service.dart';
import '../services/auth_service.dart';
import '../services/data_export_service.dart';
import '../services/data_limit_service.dart';
import '../services/local_notification_service.dart';
import '../services/usage_breakdown_service.dart';
import '../services/usage_service.dart';
import '../services/usage_sync_service.dart';

List<SingleChildWidget> buildAppProviders() {
  // Repository SQLite
  final PackageRepository packageRepo = SqlitePackageRepository();
  final QuotaCategoryRepository categoryRepo = SqliteQuotaCategoryRepository();
  final ClassificationRuleRepository ruleRepo =
      SqliteClassificationRuleRepository();
  final UsageRepository usageRepo = SqliteUsageRepository();
  final DataLimitRepository dataLimitRepo = SqliteDataLimitRepository();
  final AlertRepository alertRepo = SqliteAlertRepository();
  final SettingsRepository settingsRepo = SqliteSettingsRepository();
  final UserRepository userRepo = SqliteUserRepository();

  // Service
  final AuthService authService = FirebaseAuthService();
  final UsageService usageService = UsageServiceImpl();

  // Satu infrastruktur notifikasi lokal untuk Data Limit Warning dan Smart
  // Alerts (satu plugin, satu inisialisasi, satu alur izin).
  final LocalNotificationService localNotificationService =
      FlutterLocalNotificationService();

  final AlertService alertService = AlertServiceImpl(
    alertRepo,
    settingsRepo,
    categoryRepo: categoryRepo,
    usageRepo: usageRepo,
    sink: LocalNotificationSink(localNotificationService),
  );

  // Simulator event Smart Alerts (dipakai halaman debug).
  final AlertSimulator alertSimulator = AlertSimulator(
    sink: LocalNotificationSink(localNotificationService),
  );

  final DataLimitService dataLimitService = DataLimitService(
    dataLimitRepo,
    usageRepo,
    alertRepo,
    settingsRepo,
    localNotificationService,
  );

  final UsageSyncService usageSyncService = UsageSyncServiceImpl(
    usageService,
    usageRepo,
  );

  final AppUsageSyncService appUsageSyncService = AppUsageSyncService(
    usageService,
    usageRepo,
    categoryRepo,
  );

  final UsageBreakdownService usageBreakdownService = UsageBreakdownService(
    usageRepo,
  );

  // Ekspor seluruh data lokal akun aktif (dipakai halaman Pengaturan).
  final DataExportService dataExportService = DataExportService(
    packageRepo,
    categoryRepo,
    ruleRepo,
    usageRepo,
    dataLimitRepo,
    alertRepo,
    settingsRepo,
  );

  return [
    // Repository Provider
    Provider<PackageRepository>.value(value: packageRepo),
    Provider<QuotaCategoryRepository>.value(value: categoryRepo),
    Provider<ClassificationRuleRepository>.value(value: ruleRepo),
    Provider<UsageRepository>.value(value: usageRepo),
    Provider<DataLimitRepository>.value(value: dataLimitRepo),
    Provider<AlertRepository>.value(value: alertRepo),
    Provider<SettingsRepository>.value(value: settingsRepo),
    Provider<UserRepository>.value(value: userRepo),

    // Service Provider
    Provider<AuthService>.value(value: authService),
    Provider<UsageService>.value(value: usageService),
    Provider<AlertService>.value(value: alertService),
    Provider<LocalNotificationService>.value(value: localNotificationService),
    Provider<AlertSimulator>.value(value: alertSimulator),
    Provider<DataLimitService>.value(value: dataLimitService),
    Provider<UsageSyncService>.value(value: usageSyncService),
    Provider<AppUsageSyncService>.value(value: appUsageSyncService),
    Provider<UsageBreakdownService>.value(value: usageBreakdownService),
    Provider<DataExportService>.value(value: dataExportService),

    // ChangeNotifier Provider
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(authService, userRepo),
    ),
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(settingsRepo),
    ),
    ChangeNotifierProvider<AlertProvider>(
      create: (_) => AlertProvider(alertRepo, packageRepo),
    ),
    ChangeNotifierProvider<SettingsProvider>(
      create: (_) =>
          SettingsProvider(settingsRepo, usageService, dataExportService),
    ),
    ChangeNotifierProvider<PackageProvider>(
      create: (_) => PackageProvider(packageRepo, usageRepo: usageRepo),
    ),
    ChangeNotifierProvider<QuotaCategoryProvider>(
      create: (_) => QuotaCategoryProvider(categoryRepo),
    ),
    ChangeNotifierProvider<UsageProvider>(
      create: (_) => UsageProvider(
        usageService,
        usageRepo,
        categoryRepo,
        syncService: usageSyncService,
      ),
    ),
    ChangeNotifierProvider<DashboardProvider>(
      create: (_) => DashboardProvider(
        packageRepo,
        usageRepo,
        usageService,
        alertService,
        categoryRepo: categoryRepo,
        dataLimitRepo: dataLimitRepo,
        dataLimitService: dataLimitService,
        syncService: usageSyncService,
      ),
    ),
    ChangeNotifierProvider<DataLimitProvider>(
      create: (_) => DataLimitProvider(dataLimitService),
    ),
    ChangeNotifierProvider<UsageBreakdownProvider>(
      create: (_) => UsageBreakdownProvider(
        usageBreakdownService,
        appUsageSyncService,
        usageService,
      ),
    ),
  ];
}
