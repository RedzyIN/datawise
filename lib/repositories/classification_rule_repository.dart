import '../models/models.dart';

abstract class ClassificationRuleRepository {
  Future<String> add(ClassificationRule rule);
  Future<void> update(ClassificationRule rule);
  Future<void> delete(String ruleId);
  Future<List<ClassificationRule>> getByPackage(String packageId);
}
