// MILIK ARSITEK. KONTRAK BEKU #3.
// Kode error yang dibekukan: validation, not_found, db_error,
// permission_denied, native_error, auth_error, unknown.

class AppException implements Exception {
  final String code; // lihat daftar kode di atas
  final String message; // pesan siap tampil ke pengguna (Indonesia)

  const AppException(this.code, this.message);

  static const validation = 'validation';
  static const notFound = 'not_found';
  static const dbError = 'db_error';
  static const permissionDenied = 'permission_denied';
  static const nativeError = 'native_error';
  static const authError = 'auth_error';
  static const unknown = 'unknown';

  @override
  String toString() => 'AppException($code): $message';
}
