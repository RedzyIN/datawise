// PEMILIK: Anggota A. Nama kelas dan anggota dibekukan (kontrak #3).
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._service, [this._userRepository]) {
    // Profil lokal disimpan sebelum status authenticated diterbitkan ke UI.
    _subscription = _service.authStateChanges().listen(
      (user) {
        if (_ignoreAuthEvents) return;
        unawaited(_handleAuthStateChange(user));
      },
      onError: (_) {
        _setUser(null);
        notifyListeners();
      },
    );
  }

  static const _unknownErrorMessage = 'Terjadi kesalahan. Coba lagi.';

  final AuthService _service;
  final UserRepository? _userRepository;
  late final StreamSubscription<AppUser?> _subscription;

  // Registrasi langsung membuat sesi Firebase. Event itu ditahan sampai
  // profil lokal tersimpan dan sesi registrasi ditutup.
  bool _ignoreAuthEvents = false;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthStatus get status => _status;
  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<bool> login(String email, String password) {
    return _run(() async {
      final user = await _service.login(email, password);
      try {
        await _userRepository?.upsert(user);
      } catch (_) {
        try {
          await _service.logout();
        } catch (_) {}
        rethrow;
      }
      _setUser(user);
    });
  }

  /// Akun baru disimpan ke profil lokal, lalu pengguna kembali ke LoginPage.
  Future<bool> register(String email, String password) {
    return _run(() async {
      _ignoreAuthEvents = true;
      try {
        final user = await _service.register(email, password);
        await _userRepository?.upsert(user);
        await _service.logout();
      } catch (_) {
        try {
          await _service.logout();
        } catch (_) {}
        rethrow;
      } finally {
        _ignoreAuthEvents = false;
      }
      _setUser(null);
    });
  }

  Future<void> logout() async {
    await _run(() async {
      await _service.logout();
      // Jangan hapus profil lokal atau data paket ketika logout.
      _setUser(null);
    });
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _handleAuthStateChange(AppUser? user) async {
    try {
      if (user != null) {
        await _userRepository?.upsert(user);
      }
      _setUser(user);
    } catch (_) {
      _errorMessage = _unknownErrorMessage;
      _setUser(null);
      try {
        await _service.logout();
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = _unknownErrorMessage;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _setUser(AppUser? user) {
    _currentUser = user;
    _status = user == null
        ? AuthStatus.unauthenticated
        : AuthStatus.authenticated;
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
