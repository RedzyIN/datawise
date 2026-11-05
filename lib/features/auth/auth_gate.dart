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
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        switch (auth.status) {
          case AuthStatus.unknown:
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          case AuthStatus.authenticated:
            return const HomeShell();
          case AuthStatus.unauthenticated:
            return const LoginPage();
        }
      },
    );
  }
}
