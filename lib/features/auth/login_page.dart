// PEMILIK: Anggota A. Route '/login'.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_provider.dart';
import 'auth_validators.dart';
import 'auth_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Ditunda sampai frame selesai: notifyListeners tidak boleh saat build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    // Jika berhasil, AuthGate otomatis menampilkan /home.
    await context.read<AuthProvider>().login(
      normalizeEmail(_emailController.text),
      _passwordController.text,
    );
  }

  Future<void> _openRegister() async {
    final auth = context.read<AuthProvider>();
    _resetForm(auth);
    await Navigator.pushNamed(context, '/register');
    // Halaman login tidak dibuat ulang saat kembali, jadi bersihkan di sini.
    if (!mounted) return;
    _resetForm(auth);
  }

  /// Menghapus isian, pesan validasi di bawah kolom, dan pesan error provider.
  void _resetForm(AuthProvider auth) {
    _formKey.currentState?.reset();
    auth.clearError();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AuthColors.backgroundBottom,
      body: AuthBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AuthLogo()),
                  const SizedBox(height: 14),
                  const Center(child: AuthBadge('DATAWISE')),
                  const SizedBox(height: 18),
                  const Text(
                    'Masuk ke Akun Anda',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AuthColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pantau dan kelola penggunaan kuota internet\nharian secara cerdas',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: AuthColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AuthCard(
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthTextField(
                              label: 'Email',
                              hint: 'user@email.com',
                              icon: Icons.email_outlined,
                              controller: _emailController,
                              validator: validateEmail,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => auth.clearError(),
                            ),
                            const SizedBox(height: 20),
                            AuthTextField(
                              label: 'Kata Sandi',
                              hint: 'Masukkan kata sandi',
                              icon: Icons.lock_outline,
                              isPassword: true,
                              controller: _passwordController,
                              validator: validateLoginPassword,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onChanged: (_) => auth.clearError(),
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 24),
                            if (auth.errorMessage != null)
                              AuthErrorText(auth.errorMessage!),
                            AuthSubmitButton(
                              label: 'Masuk',
                              isLoading: auth.isLoading,
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Belum punya akun?',
                        style: TextStyle(color: AuthColors.textMuted),
                      ),
                      TextButton(
                        onPressed: _openRegister,
                        child: const Text(
                          'Daftar',
                          style: TextStyle(
                            color: AuthColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
