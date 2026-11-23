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
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _agreed = false;
  bool _showTermsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    if (!_agreed) {
      setState(() => _showTermsError = true);
    }
    if (!formValid || !_agreed) return;
    FocusScope.of(context).unfocus();

    final success = await context.read<AuthProvider>().register(
      normalizeName(_nameController.text),
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
      backgroundColor: AuthColors.backgroundBottom,
      body: AuthBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: AuthBackButton(
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Buat Akun Baru',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AuthColors.textDark,
                  ),
                ),
                const SizedBox(height: 22),
                AuthCard(
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthTextField(
                            label: 'Nama Lengkap',
                            hint: 'Nama sesuai identitas',
                            icon: Icons.person_outline,
                            controller: _nameController,
                            validator: validateName,
                            keyboardType: TextInputType.name,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => auth.clearError(),
                          ),
                          const SizedBox(height: 18),
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
                          const SizedBox(height: 18),
                          AuthTextField(
                            label: 'Kata Sandi',
                            hint: 'Minimal 6 karakter (huruf & angka)',
                            icon: Icons.lock_outline,
                            isPassword: true,
                            controller: _passwordController,
                            validator: validatePassword,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => auth.clearError(),
                          ),
                          const SizedBox(height: 18),
                          AuthTextField(
                            label: 'Konfirmasi Kata Sandi',
                            hint: 'Ulangi kata sandi',
                            icon: Icons.verified_user_outlined,
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
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: Checkbox(
                                  value: _agreed,
                                  activeColor: AuthColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  onChanged: (value) => setState(() {
                                    _agreed = value ?? false;
                                    if (_agreed) _showTermsError = false;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      color: AuthColors.textMuted,
                                      fontSize: 15,
                                      height: 1.4,
                                    ),
                                    children: [
                                      TextSpan(text: 'Saya menyetujui '),
                                      TextSpan(
                                        text: 'Syarat & Ketentuan',
                                        style: TextStyle(
                                          color: AuthColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      TextSpan(text: ' serta '),
                                      TextSpan(
                                        text: 'Kebijakan Privasi',
                                        style: TextStyle(
                                          color: AuthColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      TextSpan(text: ' DATAWISE'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_showTermsError)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 40),
                              child: Text(
                                'Anda harus menyetujui syarat dan kebijakan.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 18),
                          if (auth.errorMessage != null)
                            AuthErrorText(auth.errorMessage!),
                          AuthSubmitButton(
                            label: 'Daftar Sekarang',
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
                      'Sudah punya akun?',
                      style: TextStyle(color: AuthColors.textMuted),
                    ),
                    TextButton(
                      // pop, bukan push: kembali ke LoginPage yang sama.
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Masuk',
                        style: TextStyle(
                          color: AuthColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
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
    );
  }
}
