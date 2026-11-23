// Khusus fitur minggu 3 (Application Usage Breakdown).
//
// Menyimpan rincian per aplikasi dari NetworkStats Android ke `usage_records`
// sebagai APP_USAGE. DEVICE_TOTAL tetap ditulis memakai `source_key` yang sama
// dengan `UsageSyncServiceImpl`, sehingga pemakaian agregat perangkat tidak
// pernah tercatat dua kali. Kedua jenis catatan tidak dijumlahkan sebagai total.
import '../models/models.dart';
import '../repositories/repositories.dart';
import 'usage_service.dart';
import 'usage_sync_service.dart';

class AppUsageSyncResult {
  final UsageReading? deviceReading;
  final AppUsageReading? appReading;
  final int savedAppRecords;
  final int skippedAppRecords;

  const AppUsageSyncResult({
    required this.deviceReading,
    required this.appReading,
    required this.savedAppRecords,
    required this.skippedAppRecords,
  });
}

/// Menyimpan hasil Usage Monitor ke `usage_records`.
///
/// DEVICE_TOTAL dipakai sebagai pembanding kualitas data, sedangkan APP_USAGE
/// menjadi sumber rincian per aplikasi. Keduanya tidak pernah dijumlahkan.
/// Setiap catatan memakai `source_key` deterministik agar pembacaan bucket yang
/// sama hanya memperbarui baris lama.
class AppUsageSyncService {
  AppUsageSyncService(this._usageService, this._usageRepo, this._categoryRepo);

  final UsageService _usageService;
  final UsageRepository _usageRepo;
  final QuotaCategoryRepository _categoryRepo;

  Future<AppUsageSyncResult> syncToday(
    DataPackage package, {
    UsageReading? deviceReading,
  }) async {
    final packageId = package.id;
    if (packageId == null) {
      throw const AppException(
        AppException.validation,
        'Paket belum memiliki ID.',
      );
    }

    final now = DateTime.now();
    final start = dateOnly(now);
    final end = now.isAfter(start)
        ? now
        : start.add(const Duration(seconds: 1));

    final reading = deviceReading ?? await _usageService.refreshToday(package);

    if (reading.status == UsageReadStatus.ok && reading.totalBytes > 0) {
      // source_key sama dengan UsageSyncServiceImpl agar baris DEVICE_TOTAL
      // yang sudah ada hanya diperbarui, bukan ditambah.
      await _usageRepo.upsertRecord(
        UsageRecord(
          packageId: packageId,
          recordScope: UsageRecordScope.deviceTotal,
          networkType: NetworkType.mobile,
          periodStartAt: start,
          periodEndAt: end,
          rxBytes: reading.totalBytes,
          txBytes: 0,
          source: UsageSource.android,
          sourceKey: UsageSyncServiceImpl.sourceKeyFor(packageId, start),
          recordedAt: now,
        ),
      );
    }

    final appReading = await _usageService.readAppUsage(start, end);
    var saved = 0;
    var skipped = 0;

    if (appReading.status == UsageReadStatus.ok) {
      final mainCategory = await _mainCategoryFor(packageId);

      for (final bucket in appReading.buckets) {
        if (bucket.totalBytes <= 0) continue;

        final recordStart = bucket.start.isBefore(start) ? start : bucket.start;
        var recordEnd = bucket.end.isAfter(end) ? end : bucket.end;
        if (!recordEnd.isAfter(recordStart)) {
          recordEnd = recordStart.add(const Duration(seconds: 1));
        }

        final packageName = (bucket.packageName?.trim().isNotEmpty ?? false)
            ? bucket.packageName!.trim()
            : 'uid-${bucket.uid}';

        try {
          await _usageRepo.upsertRecordWithAllocations(
            UsageRecord(
              packageId: packageId,
              recordScope: UsageRecordScope.appUsage,
              appUid: bucket.uid,
              appPackageName: packageName,
              appName: bucket.appName,
              networkType: NetworkType.mobile,
              periodStartAt: recordStart,
              periodEndAt: recordEnd,
              rxBytes: bucket.rxBytes,
              txBytes: bucket.txBytes,
              source: UsageSource.android,
              sourceKey:
                  'android_app_${packageId}_${bucket.uid}_'
                  '${bucket.start.millisecondsSinceEpoch}_'
                  '${bucket.end.millisecondsSinceEpoch}',
              recordedAt: now,
            ),
            (usageRecordId) => [
              UsageAllocation(
                packageId: packageId,
                usageRecordId: usageRecordId,
                quotaCategoryId: mainCategory?.id,
                allocatedBytes: bucket.totalBytes,
                allocationMethod: mainCategory == null
                    ? AllocationMethod.unclassified
                    : AllocationMethod.mainFallback,
                createdAt: now,
              ),
            ],
          );
          saved++;
        } catch (_) {
          // Satu bucket yang gagal tidak menghentikan bucket lain.
          skipped++;
        }
      }
    }

    return AppUsageSyncResult(
      deviceReading: reading,
      appReading: appReading,
      savedAppRecords: saved,
      skippedAppRecords: skipped,
    );
  }

  Future<QuotaCategory?> _mainCategoryFor(String packageId) async {
    final categories = await _categoryRepo.getByPackage(packageId);

    for (final category in categories) {
      if (category.categoryType == QuotaCategoryType.main &&
          category.isEnabled) {
        return category;
      }
    }

    return null;
  }
}
