import '../models/models.dart';

abstract class UsageRepository {
  /// Saves unallocated source records such as DEVICE_TOTAL and Wi-Fi readings.
  /// Chargeable APP_USAGE and MANUAL_TOTAL records use the atomic method.
  Future<String> upsertRecord(UsageRecord record);

  /// Saves or updates a chargeable source record and all allocations
  /// in one transaction.
  Future<String> upsertRecordWithAllocations(
    UsageRecord record,
    List<UsageAllocation> allocations,
  );

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

  /// Replaces allocations on an existing record. Their sum must equal RX + TX.
  Future<void> replaceAllocations(
    String usageRecordId,
    List<UsageAllocation> allocations,
  );

  Future<List<UsageAllocation>> getAllocations(String usageRecordId);
  Future<List<UsageAllocation>> getAllocationsByPackage(String packageId);
}
