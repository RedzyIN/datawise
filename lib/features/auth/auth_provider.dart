
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider(AuthService service) : _service = service {
    // Mendengarkan perubahan status login dari Firebase.
    _authSubscription = _service.authStateChanges().listen(
      (user) {
        _currentUser = user;

        // Menentukan status berdasarkan pengguna.
        _status = user == null
            ? AuthStatus.unauthenticated
            : AuthStatus.authenticated;

        notifyListeners();
      },
      onError: (error) {
        _status = AuthStatus.unauthenticated;
        _currentUser = null;
        notifyListeners();
      },
    );
  }

  final AuthService _service;

  // Menyimpan langganan perubahan status autentikasi.
  late final StreamSubscription<AppUser?> _authSubscription;

  // Menyimpan status awal autentikasi.
  AuthStatus _status = AuthStatus.unknown;

  // Menyimpan data pengguna yang sedang login.
  AppUser? _currentUser;

  // Menandai proses login atau registrasi.
  bool _isLoading = false;

  // Menyimpan pesan kesalahan.
  String? _errorMessage;

  AuthStatus get status => _status;
  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Fungsi untuk login.
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _service.login(email, password);

      _currentUser = user;
      _status = AuthStatus.authenticated;

      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fungsi untuk registrasi akun.
  Future<bool> register(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _service.register(email, password);

      _currentUser = user;
      _status = AuthStatus.authenticated;

      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fungsi untuk logout.
  Future<void> logout() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.logout();

      _currentUser = null;
      _status = AuthStatus.unauthenticated;
    } on AppException catch (e) {
      _errorMessage = e.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Menghapus pesan kesalahan.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Menghentikan pendengar ketika provider tidak digunakan.
  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
