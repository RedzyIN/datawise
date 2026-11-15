import '../models/models.dart';

abstract class DataLimitRepository {
  Future<DataLimitSetting?> getByPackage(int packageId);
  Future<void> upsert(DataLimitSetting setting);
}
