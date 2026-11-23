// PEMILIK: Anggota A. Nama kelas dan anggota dibekukan (kontrak #3).
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._service, [this._userRepository]) {
    // Pemulihan sesi saat aplikasi dibuka kembali.
    _subscription = _service.authStateChanges().listen(
      (user) {
        if (_ignoreAuthEvents) return;
        unawaited(_handleAuthStateChange(user));
      },
      onError: (Object error, StackTrace stack) {
        logAuthFailure('authStateChanges', error, stack);
        _setUser(null);
        notifyListeners();
      },
    );
  }

  static const _unknownErrorMessage = 'Terjadi kesalahan. Coba lagi.';

  final AuthService _service;
  final UserRepository? _userRepository;
  late final StreamSubscription<AppUser?> _subscription;

  // Login/registrasi mengurus profilnya sendiri. Event sesi yang datang di
  // tengah proses ditahan agar tidak ada dua penulisan SQLite bersamaan.
  bool _ignoreAuthEvents = false;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthStatus get status => _status;
  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Menyimpan profil ke SQLite lalu melengkapi nama dari SQLite bila
  /// Firebase belum mengembalikan nama.
  ///
  /// Autentikasi Firebase dan profil lokal adalah dua sistem berbeda:
  /// kegagalan profil lokal hanya dicatat untuk developer dan tidak boleh
  /// membatalkan sesi yang sudah berhasil.
  Future<AppUser> _syncProfile(AppUser user) async {
    final repo = _userRepository;
    if (repo == null) return user;

    try {
      await repo.upsert(user);
    } catch (error, stack) {
      logAuthFailure('profile.upsert(${user.uid})', error, stack);
      return user;
    }

    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user;
    }

    try {
      final stored = await repo.getById(user.uid);
      final storedName = stored?.displayName;
      if (storedName == null || storedName.trim().isEmpty) return user;

      return AppUser(uid: user.uid, displayName: storedName, email: user.email);
    } catch (error, stack) {
      logAuthFailure('profile.getById(${user.uid})', error, stack);
      return user;
    }
  }

  Future<bool> login(String email, String password) {
    return _run(() async {
      _ignoreAuthEvents = true;
      try {
        final user = await _service.login(email, password);
        _setUser(await _syncProfile(user));
      } finally {
        _ignoreAuthEvents = false;
      }
    });
  }

  /// Akun baru (beserta nama) disimpan ke Firebase dan profil lokal,
  /// lalu pengguna kembali ke LoginPage.
  Future<bool> register(String name, String email, String password) {
    return _run(() async {
      _ignoreAuthEvents = true;
      try {
        final user = await _service.register(
          email,
          password,
          displayName: name,
        );
        await _syncProfile(user);
        await _logoutQuietly();
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
    if (user != null) {
      _setUser(await _syncProfile(user));
    } else {
      _setUser(null);
    }

    notifyListeners();
  }

  Future<void> _logoutQuietly() async {
    try {
      await _service.logout();
    } catch (error, stack) {
      logAuthFailure('logout', error, stack);
    }
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
      debugPrint('[DATAWISE auth] gagal (${e.code}): ${e.message}');
      return false;
    } on FirebaseAuthException catch (e, stack) {
      // Jaring pengaman bila ada layanan yang belum memetakan error Firebase.
      logAuthFailure('unhandled FirebaseAuthException', e, stack);
      _errorMessage = mapFirebaseAuthException(e).message;
      return false;
    } catch (error, stack) {
      logAuthFailure('unexpected', error, stack);
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
