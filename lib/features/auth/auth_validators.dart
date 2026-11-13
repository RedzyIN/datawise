// PEMILIK: Anggota A. Setiap fungsi mengembalikan null jika valid,
// atau pesan error (cocok langsung dengan `validator:` milik TextFormField).

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _hasLetter = RegExp(r'[A-Za-z]');
final _hasDigit = RegExp(r'\d');

/// Email dipotong spasi kiri-kanan dan diubah ke huruf kecil
/// sebelum divalidasi dan dikirim ke Firebase.
String normalizeEmail(String value) => value.trim().toLowerCase();

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

/// Untuk form LOGIN: hanya cek tidak kosong. Aturan panjang/huruf/angka
/// hanya berlaku saat membuat password, jadi password yang salah tetap
/// dikirim ke Firebase dan pesannya "Email atau password salah."
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
