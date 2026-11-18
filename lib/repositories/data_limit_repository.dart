import '../models/models.dart';

abstract class DataLimitRepository {
  Future<DataLimitSetting?> getByPackage(String packageId);
  Future<void> upsert(DataLimitSetting setting);
  Future<void> delete(String packageId);
}
