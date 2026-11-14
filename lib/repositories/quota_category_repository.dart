import '../models/models.dart';

abstract class QuotaCategoryRepository {
  Future<String> add(QuotaCategory category);
  Future<void> update(QuotaCategory category);
  Future<void> delete(String categoryId);
  Future<QuotaCategory?> getById(String categoryId);
  Future<List<QuotaCategory>> getByPackage(String packageId);
}
