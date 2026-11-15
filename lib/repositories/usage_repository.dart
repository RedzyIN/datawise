import '../models/models.dart';

abstract class UsageRepository {
  Future<void> upsertRecord(int packageId, DateTime date, int usedBytes, UsageSource source);
  Future<void> deleteManual(int packageId, DateTime date);
  Future<UsageRecord?> getEffectiveRecord(int packageId, DateTime date);
  Future<List<UsageRecord>> getEffectiveRecords(int packageId);
  Future<List<UsageRecord>> getRecords(int packageId);
  Future<int> getUsedBytesOn(int packageId, DateTime date);
  Future<int> getTotalUsedBytes(int packageId);
  Future<Map<DateTime, int>> getDailyUsage(int packageId);
  Future<void> replaceAllocations(int usageRecordId, List<UsageAllocation> allocations);
  Future<List<UsageAllocation>> getAllocations(int usageRecordId);
  Future<Map<int, int>> getCategoryUsage(int packageId);
}
