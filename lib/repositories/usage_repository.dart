import '../models/models.dart';

abstract class UsageRepository {
  Future<String> upsertRecord(UsageRecord record);

  Future<void> deleteManualRecords(
    String packageId,
    DateTime periodStartAt,
    DateTime periodEndAt,
  );

  Future<UsageRecord?> getById(String recordId);
  Future<List<UsageRecord>> getRecords(String packageId);

  Future<List<UsageRecord>> getRecordsForPeriod(
    String packageId,
    DateTime startAt,
    DateTime endAt,
  );

  Future<void> replaceAllocations(
    String usageRecordId,
    List<UsageAllocation> allocations,
  );

  Future<List<UsageAllocation>> getAllocations(String usageRecordId);
  Future<List<UsageAllocation>> getAllocationsByPackage(String packageId);
}
