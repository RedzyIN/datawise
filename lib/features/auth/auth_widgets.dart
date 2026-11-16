// PEMILIK: Anggota A. Komponen UI yang dipakai Login dan Register.
import 'package:flutter/material.dart';

class AuthColors {
  AuthColors._();

  static const Color primary = Color(0xFF1A66D6); // biru logo
  static const Color primaryDark = Color(0xFF1452AD);
  static const Color backgroundTop = Color(0xFFDCEBFF);
  static const Color backgroundBottom = Color(0xFFF7FBFF);
  static const Color field = Color(0xFFE3EFFD);
  static const Color fieldBorder = Color(0xFFCFE2F9);
  static const Color chip = Color(0xFFCFE2FB);
  static const Color textDark = Color(0xFF0F1F3D);
  static const Color textMuted = Color(0xFF51617A);
  static const Color hint = Color(0xFF8394AD);
  static const Color icon = Color(0xFF5B6B84);
}

/// Latar gradasi biru muda ke putih.
class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AuthColors.backgroundTop, AuthColors.backgroundBottom],
        ),
      ),
      child: child,
    );
  }
}

/// Kartu putih membulat tempat form berada.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AuthColors.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Logo aplikasi di dalam wadah halo membulat.
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(size * 0.36),
        boxShadow: [
          BoxShadow(
            color: AuthColors.primary.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: Image.asset(
          'assets/images/logo_datawise.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(
            Icons.data_usage_rounded,
            size: size,
            color: AuthColors.primary,
          ),
        ),
      ),
    );
  }
}

/// Label kecil berbentuk pil (contoh: "DATAWISE").
class AuthBadge extends StatelessWidget {
  const AuthBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AuthColors.chip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AuthColors.primaryDark,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Kolom isian dengan label di atas. Jika [isPassword], ada ikon
/// tampilkan/sembunyikan password.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.hint,
    this.helper,
    this.validator,
    this.isPassword = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.trailingLabel,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final String? helper;
  final String? Function(String?)? validator;
  final bool isPassword;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final int? maxLength;

  /// Widget di kanan label (contoh: tautan "Lupa Kata Sandi?").
  final Widget? trailingLabel;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _hidden = true;

  OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AuthColors.textDark,
                fontSize: 15,
              ),
            ),
            if (widget.trailingLabel != null) widget.trailingLabel!,
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          obscureText: widget.isPassword && _hidden,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          // Batas panjang dicek validator, bukan dipotong diam-diam.
          maxLength: null,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          style: const TextStyle(color: AuthColors.textDark, fontSize: 16),
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helper,
            helperMaxLines: 2,
            hintStyle: const TextStyle(color: AuthColors.hint),
            filled: true,
            fillColor: AuthColors.field,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            prefixIcon: Icon(widget.icon, color: AuthColors.icon),
            suffixIcon: widget.isPassword
                ? IconButton(
                    tooltip: _hidden
                        ? 'Tampilkan password'
                        : 'Sembunyikan password',
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AuthColors.icon,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
            border: _border(Colors.transparent),
            enabledBorder: _border(AuthColors.fieldBorder.withValues(alpha: 0)),
            focusedBorder: _border(AuthColors.primary, 1.6),
            errorBorder: _border(errorColor),
            focusedErrorBorder: _border(errorColor, 1.6),
          ),
        ),
      ],
    );
  }
}

/// Pesan error dari provider (teks merah), tampil di atas tombol.
class AuthErrorText extends StatelessWidget {
  const AuthErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// Tombol utama membulat dengan ikon panah. Nonaktif dan menampilkan
/// indikator saat [isLoading].
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AuthColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AuthColors.primary.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 22),
                ],
              ),
      ),
    );
  }
}

/// Tombol kembali persegi membulat.
class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: const SizedBox(
          width: 52,
          height: 52,
          child: Icon(Icons.arrow_back_rounded, color: AuthColors.primary),
        ),
      ),
    );
  }
}
