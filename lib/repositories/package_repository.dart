// MILIK ARSITEK. KONTRAK BEKU #4.
import '../models/models.dart';

abstract class PackageRepository {
  Future<int> add(DataPackage p); // jika isActive, paket lain user itu jadi nonaktif
  Future<void> update(DataPackage p);
  Future<void> delete(int id);
  Future<DataPackage?> getById(int id);
  Future<DataPackage?> getActive(String userId);
  Future<List<DataPackage>> getAll(String userId); // terbaru dulu
  Future<void> setActive(String userId, int packageId);
}
