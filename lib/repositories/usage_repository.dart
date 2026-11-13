// MILIK ARSITEK. KONTRAK BEKU #4.
import '../models/models.dart';

abstract class UsageRepository {
  Future<void> upsertRecord(
      int packageId, DateTime date, int usedBytes, UsageSource source);
  Future<void> deleteManual(int packageId, DateTime date);
  Future<List<UsageRecord>> getRecords(int packageId);
  Future<int> getUsedBytesOn(int packageId, DateTime date); // pemakaian efektif hari itu
  Future<int> getTotalUsedBytes(int packageId); // sudah termasuk initial_used_bytes
  Future<Map<DateTime, int>> getDailyUsage(int packageId); // untuk grafik
}
