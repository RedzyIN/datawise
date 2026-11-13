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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Selamat Datang!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Silakan masuk ke akun DATAWISE Anda',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 40),
                    AuthTextField(
                      label: 'Email',
                      hint: 'Masukkan email Anda',
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
                      label: 'Password',
                      hint: 'Masukkan password Anda',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      controller: _passwordController,
                      validator: validateLoginPassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => auth.clearError(),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 28),
                    if (auth.errorMessage != null)
                      AuthErrorText(auth.errorMessage!),
                    AuthSubmitButton(
                      label: 'Masuk',
                      isLoading: auth.isLoading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Belum punya akun?'),
                        TextButton(
                          onPressed: _openRegister,
                          child: const Text('Daftar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
