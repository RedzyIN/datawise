// PEMILIK: Anggota A. Route '/'.
// unknown -> layar tunggu | authenticated -> HomeShell | unauthenticated -> LoginPage
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/home_shell.dart';
import 'auth_provider.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // select: hanya dibangun ulang saat status berubah.
    final status = context.select((AuthProvider auth) => auth.status);

    return switch (status) {
      AuthStatus.unknown => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AuthStatus.authenticated => const HomeShell(),
      AuthStatus.unauthenticated => const LoginPage(),
    };
  }
}
