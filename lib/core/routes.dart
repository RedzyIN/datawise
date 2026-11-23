// Route yang dibekukan (jangan tambah/ubah tanpa pengumuman).
import 'package:flutter/widgets.dart';

import '../features/auth/auth_gate.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/data_limit/data_limit_page.dart';
import '../features/package/package_detail_page.dart';
import '../features/package/package_form_page.dart';
import '../features/package/quota_category_form_page.dart';
import '../features/usage_monitor/usage_manual_page.dart';

abstract class Routes {
  static const gate = '/';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const packageForm =
      '/package/form'; // arg: DataPackage? (null = tambah)
  static const packageDetail = '/package/detail'; // arg: int (id paket)
  static const quotaCategoryForm =
      '/package/category/form'; // arg: QuotaCategoryFormArgs
  static const usageManual = '/usage/manual'; // arg: DataPackage
  static const dataLimit = '/usage/data-limit'; // arg: DataPackage
}

final Map<String, WidgetBuilder> appRoutes = {
  Routes.gate: (_) => const AuthGate(),
  Routes.login: (_) => const LoginPage(),
  Routes.register: (_) => const RegisterPage(),
  // Dijaga AuthGate: hanya menampilkan HomeShell jika sudah login.
  Routes.home: (_) => const AuthGate(),
  Routes.packageForm: (_) => const PackageFormPage(),
  Routes.packageDetail: (_) => const PackageDetailPage(),
  Routes.quotaCategoryForm: (_) => const QuotaCategoryFormPage(),
  Routes.usageManual: (_) => const UsageManualPage(),
  Routes.dataLimit: (_) => const DataLimitPage(),
};
