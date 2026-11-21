// MILIK ARSITEK. Satu-satunya tempat mendaftarkan Repository, Service, dan Provider.

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../features/auth/auth_provider.dart';
import '../features/dashboard/dashboard_provider.dart';
import '../features/data_limit/data_limit_provider.dart';
import '../features/package/package_provider.dart';
import '../features/usage_monitor/usage_provider.dart';
import '../repositories/repositories.dart';
import '../services/alert_service.dart';
import '../services/auth_service.dart';
import '../services/data_limit_service.dart';
import '../services/local_notification_service.dart';
import '../services/usage_service.dart';

List<SingleChildWidget> buildAppProviders() {
  // --- Repository SQLite ---
  final PackageRepository packageRepo = SqlitePackageRepository();

  final QuotaCategoryRepository categoryRepo = SqliteQuotaCategoryRepository();

  final ClassificationRuleRepository ruleRepo =
      SqliteClassificationRuleRepository();

  final UsageRepository usageRepo = SqliteUsageRepository();

  final DataLimitRepository dataLimitRepo = SqliteDataLimitRepository();

  final AlertRepository alertRepo = SqliteAlertRepository();

  final SettingsRepository settingsRepo = SqliteSettingsRepository();

  final UserRepository userRepo = SqliteUserRepository();

  // --- Service ---
  final AuthService authService = FirebaseAuthService();

  final UsageService usageService = UsageServiceImpl();

  final AlertService alertService = AlertServiceImpl(alertRepo, settingsRepo);

  final LocalNotificationService localNotificationService =
      FlutterLocalNotificationService();

  final DataLimitService dataLimitService = DataLimitService(
    dataLimitRepo,
    usageRepo,
    alertRepo,
    settingsRepo,
    localNotificationService,
  );

  return [
    Provider<PackageRepository>.value(value: packageRepo),

    Provider<QuotaCategoryRepository>.value(value: categoryRepo),

    Provider<ClassificationRuleRepository>.value(value: ruleRepo),

    Provider<UsageRepository>.value(value: usageRepo),

    Provider<DataLimitRepository>.value(value: dataLimitRepo),

    Provider<AlertRepository>.value(value: alertRepo),

    Provider<SettingsRepository>.value(value: settingsRepo),

    Provider<UserRepository>.value(value: userRepo),

    Provider<AuthService>.value(value: authService),

    Provider<UsageService>.value(value: usageService),

    Provider<AlertService>.value(value: alertService),

    Provider<LocalNotificationService>.value(
      value: localNotificationService,
    ),

    Provider<DataLimitService>.value(value: dataLimitService),

    // --- Provider ---
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(authService, userRepo),
    ),

    ChangeNotifierProvider<PackageProvider>(
      create: (_) => PackageProvider(packageRepo),
    ),

    ChangeNotifierProvider<UsageProvider>(
      create: (_) => UsageProvider(usageService, usageRepo, categoryRepo),
    ),

    ChangeNotifierProvider<DashboardProvider>(
      create: (_) =>
          DashboardProvider(packageRepo, usageRepo, usageService, alertService),
    ),

    ChangeNotifierProvider<DataLimitProvider>(
      create: (_) => DataLimitProvider(dataLimitService),
    ),
  ];
}
