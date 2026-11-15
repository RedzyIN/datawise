import '../models/app_user.dart';

/// Local profile linked to the Firebase Authentication UID.
abstract class UserRepository {
  Future<void> upsert(AppUser user);
  Future<AppUser?> getById(String uid);
}
