// MILIK ARSITEK. KONTRAK BEKU #4.
import '../models/models.dart';

abstract class AlertRepository {
  Future<bool> hasBeenSent(int packageId, AlertType type, DateTime alertDate);
  Future<void> markSent(int packageId, AlertType type, DateTime alertDate);
}
