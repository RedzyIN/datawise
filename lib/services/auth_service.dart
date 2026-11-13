// PEMILIK: Anggota A. KONTRAK BEKU #4 - nama & bentuk tidak boleh diubah.
// TODO(A): isi FirebaseAuthService (FirebaseAuth? opsional di konstruktor),
// mapFirebaseAuthException, dan konversi User? -> AppUser?.
import '../models/models.dart';

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<AppUser> register(String email, String password);
  Future<AppUser> login(String email, String password);
  Future<void> logout();
}

class FirebaseAuthService implements AuthService {
  // TODO(A): FirebaseAuthService([FirebaseAuth? auth])
  @override
  Stream<AppUser?> authStateChanges() => const Stream<AppUser?>.empty();

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser> register(String email, String password) =>
      throw UnimplementedError('TODO(A)');

  @override
  Future<AppUser> login(String email, String password) =>
      throw UnimplementedError('TODO(A)');

  @override
  Future<void> logout() => throw UnimplementedError('TODO(A)');
}
