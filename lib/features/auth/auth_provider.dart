// PEMILIK: Anggota A. Nama kelas dan anggota dibekukan (kontrak #3).
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._service) {
    // Dengarkan status login dari Firebase sekali saja.
    _subscription = _service.authStateChanges().listen(
      (user) {
        if (_ignoreAuthEvents) return;
        _setUser(user);
        notifyListeners();
      },
      onError: (_) {
        _setUser(null);
        notifyListeners();
      },
    );
  }

  static const _unknownErrorMessage = 'Terjadi kesalahan. Coba lagi.';

  final AuthService _service;
  late final StreamSubscription<AppUser?> _subscription;

  // true selama registrasi: Firebase otomatis login setelah daftar, tetapi
  // kita ingin pengguna kembali ke LoginPage, jadi event itu diabaikan agar
  // HomeShell tidak sempat tampil sekilas.
  bool _ignoreAuthEvents = false;

  AuthStatus _status = AuthStatus.unknown; // unknown = Firebase belum menjawab
  AppUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthStatus get status => _status;
  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// true = berhasil.
  Future<bool> login(String email, String password) {
    return _run(() async => _setUser(await _service.login(email, password)));
  }

  /// true = berhasil. Akun dibuat, lalu langsung di-logout supaya pengguna
  /// kembali ke LoginPage dan masuk dengan akun barunya.
  Future<bool> register(String email, String password) {
    return _run(() async {
      _ignoreAuthEvents = true;
      try {
        await _service.register(email, password);
        await _service.logout();
      } finally {
        _ignoreAuthEvents = false;
      }
      _setUser(null);
    });
  }

  Future<void> logout() async {
    await _run(() async {
      await _service.logout();
      _setUser(null);
    });
  }

  void clearError() {
    if (_errorMessage == null) return; // tidak ada yang perlu diperbarui
    _errorMessage = null;
    notifyListeners();
  }

  /// Menjalankan aksi dengan pola yang sama: loading -> coba -> tangkap error.
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
