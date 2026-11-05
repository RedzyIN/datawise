// PEMILIK: Anggota A. KONTRAK BEKU - nama kelas & anggota dibekukan.
// TODO(A): dengarkan authStateChanges() sekali di konstruktor; tangkap AppException.
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider(AuthService service) : _service = service;

  // ignore: unused_field
  final AuthService _service;

  AuthStatus get status => AuthStatus.unauthenticated; // unknown = Firebase belum menjawab
  AppUser? get currentUser => null;
  bool get isLoading => false;
  String? get errorMessage => null;

  Future<bool> login(String email, String password) async =>
      throw UnimplementedError('TODO(A)');
  Future<bool> register(String email, String password) async =>
      throw UnimplementedError('TODO(A)');
  Future<void> logout() async => throw UnimplementedError('TODO(A)');
  void clearError() {}
}
