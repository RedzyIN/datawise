import '../models/models.dart';

abstract class AlertRepository {
  Future<String> add(AlertLog alert);
  Future<bool> existsByDedupeKey(String dedupeKey);
  Future<List<AlertLog>> getByPackage(String packageId);
  Future<void> markRead(String alertId);
  Future<void> markAllRead(String packageId);
}
