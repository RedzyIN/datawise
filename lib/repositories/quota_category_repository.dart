import '../models/models.dart';

abstract class QuotaCategoryRepository {
  Future<int> add(QuotaCategory category);
  Future<void> update(QuotaCategory category);
  Future<void> delete(int categoryId);
  Future<QuotaCategory?> getById(int categoryId);
  Future<List<QuotaCategory>> getByPackage(int packageId);
}
