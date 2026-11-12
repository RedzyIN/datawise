
// PEMILIK: Anggota A. Mengembalikan null jika valid, atau pesan error.

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Email tidak boleh kosong';
  }

  final email = value.trim();

  final emailRegex = RegExp(
    r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$',
  );

  if (!emailRegex.hasMatch(email)) {
    return 'Format email tidak valid';
  }

  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Password tidak boleh kosong';
  }

  if (value.length < 6) {
    return 'Password minimal 6 karakter';
  }

  return null;
}

String? validateConfirmPassword(String? password, String? confirm) {
  if (confirm == null || confirm.isEmpty) {
    return 'Konfirmasi password tidak boleh kosong';
  }

  if (password != confirm) {
    return 'Konfirmasi password tidak cocok';
  }

  return null;
}
