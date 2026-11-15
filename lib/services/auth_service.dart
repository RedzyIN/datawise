
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

AppException mapFirebaseAuthException(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return const AppException(
        AppException.validation,
        'Format email tidak valid.',
      );

    case 'email-already-in-use':
      return const AppException(
        AppException.authError,
        'Email sudah terdaftar.',
      );

    case 'weak-password':
      return const AppException(
        AppException.validation,
        'Password terlalu lemah.',
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
        'Koneksi internet bermasalah.',
      );

    default:
      return const AppException(
        AppException.unknown,
        'Terjadi kesalahan. Silakan coba lagi.',
      );
  }
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<AppUser> register(String email, String password);
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
      email: user.email ?? '',
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
  Future<AppUser> register(String email, String password) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = _toAppUser(result.user);

      if (user == null) {
        throw const AppException(
          AppException.authError,
          'Registrasi gagal. Data pengguna tidak ditemukan.',
        );
      }

      return user;
    } on FirebaseAuthException catch (e) {
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
    } on FirebaseAuthException catch (e) {
      throw mapFirebaseAuthException(e);
    }
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
  }
}
