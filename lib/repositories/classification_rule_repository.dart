import '../models/models.dart';

abstract class ClassificationRuleRepository {
  Future<int> add(ClassificationRule rule);
  Future<void> update(ClassificationRule rule);
  Future<void> delete(int ruleId);
  Future<List<ClassificationRule>> getByPackage(int packageId);
}
