import '../models/models.dart';

abstract class PackageRepository {
  Future<String> add(DataPackage package);
  Future<void> update(DataPackage package);
  Future<void> delete(String packageId);
  Future<DataPackage?> getById(String packageId);
  Future<DataPackage?> getActive(String userId);
  Future<List<DataPackage>> getAll(String userId);
  Future<void> setActive(String userId, String packageId);
}
