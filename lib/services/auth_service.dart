import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Mencatat kegagalan autentikasi/persistensi ke debug console.
///
/// Hanya untuk pesan error dan stack trace. Jangan pernah mengirim password,
/// token, atau data sensitif lain ke fungsi ini.
void logAuthFailure(String operation, Object error, [StackTrace? stack]) {
  debugPrint('[DATAWISE auth] $operation gagal: $error');
  if (stack != null) {
    debugPrintStack(stackTrace: stack, label: '[DATAWISE auth] $operation');
  }
}

AppException mapFirebaseAuthException(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return const AppException(
        AppException.validation,
        'Format email tidak valid.',
      );

    case 'missing-password':
      return const AppException(
        AppException.validation,
        'Password wajib diisi.',
      );

    case 'email-already-in-use':
    case 'credential-already-in-use':
      return const AppException(
        AppException.authError,
        'Email sudah terdaftar. Silakan masuk.',
      );

    case 'weak-password':
      return const AppException(
        AppException.validation,
        'Password terlalu lemah (minimal 6 karakter).',
      );

    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return const AppException(
        AppException.authError,
        'Email atau password salah.',
      );

    case 'user-disabled':
      return const AppException(
        AppException.authError,
        'Akun ini telah dinonaktifkan.',
      );

    case 'too-many-requests':
      return const AppException(
        AppException.authError,
        'Terlalu banyak percobaan. Coba lagi nanti.',
      );

    case 'network-request-failed':
      return const AppException(
        AppException.authError,
        'Koneksi internet bermasalah. Periksa jaringan lalu coba lagi.',
      );

    case 'operation-not-allowed':
      return const AppException(
        AppException.authError,
        'Metode login Email/Password belum diaktifkan di Firebase Console.',
      );

    case 'api-key-not-valid':
    case 'invalid-api-key':
    case 'app-not-authorized':
    case 'configuration-not-found':
    case 'project-not-found':
    case 'unauthorized-domain':
      return const AppException(
        AppException.authError,
        'Konfigurasi Firebase aplikasi tidak cocok. Hubungi pengembang.',
      );

    case 'channel-error':
    case 'internal-error':
      return const AppException(
        AppException.authError,
        'Layanan Firebase tidak merespons. Coba lagi.',
      );

    case 'requires-recent-login':
      return const AppException(
        AppException.authError,
        'Sesi sudah terlalu lama. Silakan masuk ulang.',
      );

    default:
      return AppException(
        AppException.unknown,
        'Autentikasi gagal (${e.code}). Coba lagi.',
      );
  }
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<AppUser> register(
    String email,
    String password, {
    String? displayName,
  });
  Future<AppUser> login(String email, String password);
  Future<void> logout();
}

class FirebaseAuthService implements AuthService {
  // Menggunakan FirebaseAuth bawaan jika tidak ada yang diberikan.
  FirebaseAuthService([FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  // Mengubah User Firebase menjadi AppUser aplikasi.
  AppUser? _toAppUser(User? user) {
    if (user == null) return null;

    return AppUser(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
    );
  }

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.authStateChanges().map(_toAppUser);
  }

  @override
  AppUser? get currentUser {
    return _toAppUser(_auth.currentUser);
  }

  @override
  Future<AppUser> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final created = result.user;
      if (created == null) {
        throw const AppException(
          AppException.authError,
          'Registrasi gagal. Data pengguna tidak ditemukan.',
        );
      }

      // Akun Firebase sudah jadi di titik ini. Nama tampilan bersifat
      // pelengkap: kegagalannya tidak boleh membuat registrasi dianggap gagal.
      final name = displayName?.trim();
      if (name != null && name.isNotEmpty) {
        try {
          await created.updateDisplayName(name);
          await created.reload();
        } catch (error, stack) {
          logAuthFailure('register.updateDisplayName', error, stack);
        }
      }

      return AppUser(
        uid: created.uid,
        displayName: (created.displayName?.trim().isEmpty ?? true)
            ? name
            : created.displayName,
        email: created.email,
      );
    } on FirebaseAuthException catch (e, stack) {
      logAuthFailure('register', e, stack);
      throw mapFirebaseAuthException(e);
    }
  }

  @override
  Future<AppUser> login(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = _toAppUser(result.user);

      if (user == null) {
        throw const AppException(
          AppException.authError,
          'Login gagal. Data pengguna tidak ditemukan.',
        );
      }

      return user;
    } on FirebaseAuthException catch (e, stack) {
      logAuthFailure('login', e, stack);
      throw mapFirebaseAuthException(e);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (e, stack) {
      logAuthFailure('logout', e, stack);
      throw mapFirebaseAuthException(e);
    }
  }
}
