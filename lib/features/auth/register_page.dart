// PEMILIK: Anggota A. Route '/register'.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_provider.dart';
import 'auth_validators.dart';
import 'auth_widgets.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await context.read<AuthProvider>().register(
      normalizeEmail(_emailController.text),
      _passwordController.text,
    );

    // Akun sudah dibuat dan di-logout. Tutup halaman ini agar AuthGate
    // menampilkan LoginPage. SnackBar tetap tampil karena milik root.
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Akun berhasil dibuat. Silakan masuk.')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(),
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
                      'Buat Akun',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Daftar untuk mulai menggunakan DATAWISE',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 35),
                    AuthTextField(
                      label: 'Email',
                      hint: 'Masukkan email',
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
                      hint: 'Masukkan password',
                      helper: 'Minimal 6 karakter, harus ada huruf dan angka.',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      controller: _passwordController,
                      validator: validatePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => auth.clearError(),
                    ),
                    const SizedBox(height: 20),
                    AuthTextField(
                      label: 'Konfirmasi Password',
                      hint: 'Ulangi password',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      controller: _confirmController,
                      validator: (value) => validateConfirmPassword(
                        _passwordController.text,
                        value,
                      ),
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => auth.clearError(),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 28),
                    if (auth.errorMessage != null)
                      AuthErrorText(auth.errorMessage!),
                    AuthSubmitButton(
                      label: 'Daftar',
                      isLoading: auth.isLoading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Sudah punya akun?'),
                        TextButton(
                          // pop, bukan push: kembali ke LoginPage yang sama.
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Masuk'),
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
