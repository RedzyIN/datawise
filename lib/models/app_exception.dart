class AppException implements Exception {
  final String code;
  final String message;
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
