// PEMILIK: Anggota A. Setiap fungsi mengembalikan null jika valid,
// atau pesan error (cocok langsung dengan `validator:` milik TextFormField).

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _hasLetter = RegExp(r'[A-Za-z]');
final _hasDigit = RegExp(r'\d');
final _multiSpace = RegExp(r'\s+');

const int nameMinLength = 2;
const int nameMaxLength = 100;

/// Email dipotong spasi kiri-kanan dan diubah ke huruf kecil
/// sebelum divalidasi dan dikirim ke Firebase.
String normalizeEmail(String value) => value.trim().toLowerCase();

/// Nama dipotong spasi kiri-kanan dan spasi berulang dijadikan satu.
String normalizeName(String value) => value.trim().replaceAll(_multiSpace, ' ');

String? validateName(String? value) {
  final name = normalizeName(value ?? '');
  if (name.isEmpty) return 'Nama lengkap wajib diisi.';
  if (name.length < nameMinLength) return 'Nama minimal 2 karakter.';
  if (name.length > nameMaxLength) return 'Nama maksimal 100 karakter.';
  return null;
}

String? validateEmail(String? value) {
  final email = normalizeEmail(value ?? '');
  if (email.isEmpty) return 'Email wajib diisi.';
  if (!_emailPattern.hasMatch(email)) return 'Format email tidak valid.';
  return null;
}

/// Password tidak dipotong dan tidak diubah.
String? validatePassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Password wajib diisi.';
  if (password.length < 6) return 'Password minimal 6 karakter.';
  if (password.length > 64) return 'Password maksimal 64 karakter.';
  if (!_hasLetter.hasMatch(password) || !_hasDigit.hasMatch(password)) {
    return 'Password harus mengandung huruf dan angka.';
  }
  return null;
}

/// Untuk form LOGIN: hanya cek tidak kosong.
String? validateLoginPassword(String? value) {
  if (value == null || value.isEmpty) return 'Password wajib diisi.';
  return null;
}

String? validateConfirmPassword(String? password, String? confirm) {
  if (confirm == null || confirm.isEmpty) {
    return 'Konfirmasi password wajib diisi.';
  }
  if (password != confirm) return 'Konfirmasi password tidak sama.';
  return null;
}
