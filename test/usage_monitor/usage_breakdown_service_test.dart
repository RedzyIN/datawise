import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/core/constants.dart';
import 'package:datawise/features/usage_breakdown/usage_format.dart';
import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/in_memory/in_memory_repositories.dart';
import 'package:datawise/services/usage_breakdown_service.dart';
import 'package:datawise/services/usage_service.dart';
import 'package:datawise/services/app_usage_sync_service.dart';
import 'package:datawise/services/usage/usage_classification_service.dart';

class FakeUsageMonitorService implements UsageService {
  UsageReading? deviceReading;
  AppUsageReading? appReading;
  int appCallCount = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<bool> openInternetSettings() async => true;

  @override
  Future<UsageReading> readMobileUsage(DateTime start, DateTime end) async {
    return deviceReading ??
        UsageReading(
          status: UsageReadStatus.ok,
          totalBytes: 0,
          start: start,
          end: end,
          message: null,
        );
  }

  @override
  Future<AppUsageReading> readAppUsage(DateTime start, DateTime end) async {
    appCallCount++;
    return appReading ??
        AppUsageReading(
          status: UsageReadStatus.ok,
          buckets: const [],
          start: start,
          end: end,
          message: null,
        );
  }

  @override
  Future<UsageReading> refreshToday(DataPackage package) async {
    final now = DateTime.now();
    return readMobileUsage(dateOnly(now), now);
  }
}

void main() {
  late InMemoryPackageRepository packageRepo;
  late InMemoryQuotaCategoryRepository categoryRepo;
  late InMemoryClassificationRuleRepository ruleRepo;
  late InMemoryUsageRepository usageRepo;
  late FakeUsageMonitorService monitor;
  late AppUsageSyncService syncService;
  late UsageBreakdownService breakdownService;
  late DataPackage package;

  late DateTime now;
  late DateTime dayStart;
  late DateTime bucketStart;
  late DateTime bucketEnd;

  const userId = 'user-1';

  setUp(() async {
    packageRepo = InMemoryPackageRepository();
    categoryRepo = InMemoryQuotaCategoryRepository(packageRepo);
    ruleRepo = InMemoryClassificationRuleRepository(packageRepo, categoryRepo);
    usageRepo = InMemoryUsageRepository(packageRepo, categoryRepo, ruleRepo);
    monitor = FakeUsageMonitorService();
    syncService = AppUsageSyncService(
      monitor,
      usageRepo,
      UsageClassificationService(
        ruleRepository: ruleRepo,
        categoryRepository: categoryRepo,
        usageRepository: usageRepo,
      ),
    );
    breakdownService = UsageBreakdownService(usageRepo);

    now = DateTime.now();
    dayStart = dateOnly(now);
    bucketStart = dayStart.add(const Duration(hours: 1));
    bucketEnd = bucketStart.add(const Duration(hours: 1));

    final id = await packageRepo.add(
      DataPackage(
        userId: userId,
        packageName: 'Paket Uji',
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 10 * kBytesPerGB,
        startDate: dayStart,
        endDate: dayStart.add(const Duration(days: 30)),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );

    package = (await packageRepo.getById(id))!;
  });

  void setReadings({
    int deviceBytes = 10 * kBytesPerMB,
    int instagramRxBytes = 5 * kBytesPerMB,
    int instagramTxBytes = 1 * kBytesPerMB,
    String? instagramPackageName = 'com.instagram.android',
    int youtubeBytes = 4 * kBytesPerMB,
  }) {
    monitor.deviceReading = UsageReading(
      status: UsageReadStatus.ok,
      totalBytes: deviceBytes,
      start: dayStart,
      end: now,
      message: null,
    );

    monitor.appReading = AppUsageReading(
      status: UsageReadStatus.ok,
      buckets: [
        AppUsageBucket(
          uid: 101,
          packageName: instagramPackageName,
          appName: 'Instagram',
          rxBytes: instagramRxBytes,
          txBytes: instagramTxBytes,
          start: bucketStart,
          end: bucketEnd,
        ),
        AppUsageBucket(
          uid: 102,
          packageName: 'com.google.android.youtube',
          appName: 'YouTube',
          rxBytes: youtubeBytes,
          txBytes: 0,
          start: bucketStart,
          end: bucketEnd,
        ),
      ],
      start: dayStart,
      end: now,
      message: null,
    );
  }

  Future<String> mainCategoryId() async {
    final categories = await categoryRepo.getByPackage(package.id!);
    return categories
        .firstWhere(
          (category) => category.categoryType == QuotaCategoryType.main,
        )
        .id!;
  }

  group('AppUsageSyncService - Sumber data yang sama', () {
    test('menyimpan DEVICE_TOTAL dan APP_USAGE ke usage_records', () async {
      setReadings();

      final result = await syncService.syncToday(package);

      expect(result.savedAppRecords, 2);
      expect(monitor.appCallCount, 1);

      final records = await usageRepo.getRecords(package.id!);

      expect(records.length, 3);

      final device = records.singleWhere(
        (record) => record.recordScope == UsageRecordScope.deviceTotal,
      );
      expect(device.totalBytes, 10 * kBytesPerMB);
      expect(device.source, UsageSource.android);

      final apps = records
          .where((record) => record.recordScope == UsageRecordScope.appUsage)
          .toList();

      expect(apps.length, 2);
      expect(apps.map((record) => record.appPackageName).toSet(), {
        'com.instagram.android',
        'com.google.android.youtube',
      });

      final instagram = apps.singleWhere(
        (record) => record.appPackageName == 'com.instagram.android',
      );
      expect(instagram.totalBytes, 6 * kBytesPerMB);
      expect(instagram.appName, 'Instagram');
      expect(instagram.sourceKey, isNotNull);

      final allocations = await usageRepo.getAllocations(instagram.id!);
      expect(allocations.single.allocatedBytes, 6 * kBytesPerMB);
      expect(
        allocations.single.allocationMethod,
        AllocationMethod.mainFallback,
      );
      expect(allocations.single.quotaCategoryId, await mainCategoryId());
    });

    test(
      'sinkronisasi ulang memperbarui catatan dengan source_key sama',
      () async {
        setReadings();
        await syncService.syncToday(package);

        setReadings(
          instagramRxBytes: 6 * kBytesPerMB,
          instagramTxBytes: 1 * kBytesPerMB,
        );
        await syncService.syncToday(package);

        final records = await usageRepo.getRecords(package.id!);
        expect(records.length, 3);

        final instagram = records.singleWhere(
          (record) => record.appPackageName == 'com.instagram.android',
        );
        expect(instagram.totalBytes, 7 * kBytesPerMB);

        final allocations = await usageRepo.getAllocations(instagram.id!);
        expect(allocations.single.allocatedBytes, 7 * kBytesPerMB);
      },
    );

    test(
      'bucket tanpa nama paket tetap disimpan dengan identitas UID',
      () async {
        setReadings(instagramPackageName: null);

        await syncService.syncToday(package);

        final apps = (await usageRepo.getRecords(package.id!))
            .where((record) => record.recordScope == UsageRecordScope.appUsage)
            .toList();

        expect(
          apps.map((record) => record.appPackageName),
          contains('uid-101'),
        );
      },
    );

    test(
      'pembacaan per aplikasi gagal tidak menghapus total perangkat',
      () async {
        setReadings();
        monitor.appReading = AppUsageReading(
          status: UsageReadStatus.permissionDenied,
          buckets: const [],
          start: dayStart,
          end: now,
          message: 'Izin ditolak.',
        );

        final result = await syncService.syncToday(package);

        expect(result.savedAppRecords, 0);

        final records = await usageRepo.getRecords(package.id!);
        expect(records.length, 1);
        expect(records.single.recordScope, UsageRecordScope.deviceTotal);
      },
    );
  });

  group('UsageBreakdownService - Nama tampilan aplikasi', () {
    test('label kosong diubah menjadi nama UID yang mudah dibaca', () async {
      final categoryId = await mainCategoryId();

      await usageRepo.upsertRecordWithAllocations(
        UsageRecord(
          packageId: package.id!,
          recordScope: UsageRecordScope.appUsage,
          appUid: 10123,
          appPackageName: 'uid-10123',
          networkType: NetworkType.mobile,
          periodStartAt: bucketStart,
          periodEndAt: bucketEnd,
          rxBytes: 2 * kBytesPerMB,
          txBytes: 0,
          source: UsageSource.android,
          sourceKey: 'unknown_uid',
          recordedAt: now,
        ),
        (usageRecordId) => [
          UsageAllocation(
            packageId: package.id!,
            usageRecordId: usageRecordId,
            quotaCategoryId: categoryId,
            allocatedBytes: 2 * kBytesPerMB,
            allocationMethod: AllocationMethod.mainFallback,
            createdAt: now,
          ),
        ],
      );

      final breakdown = await breakdownService.build(
        packageId: package.id!,
        now: now,
      );

      expect(breakdown.apps.single.appName, 'Aplikasi UID 10123');
    });

    test('label diambil dari catatan lain yang punya nama', () async {
      final later = bucketStart.add(const Duration(hours: 1));
      final categoryId = await mainCategoryId();

      for (final entry in [
        (name: null, start: bucketStart),
        (name: 'Instagram', start: later),
      ]) {
        await usageRepo.upsertRecordWithAllocations(
          UsageRecord(
            packageId: package.id!,
            recordScope: UsageRecordScope.appUsage,
            appUid: 101,
            appPackageName: 'com.instagram.android',
            appName: entry.name,
            networkType: NetworkType.mobile,
            periodStartAt: entry.start,
            periodEndAt: entry.start.add(const Duration(hours: 1)),
            rxBytes: 2 * kBytesPerMB,
            txBytes: 0,
            source: UsageSource.android,
            sourceKey: 'named_${entry.start.millisecondsSinceEpoch}',
            recordedAt: now,
          ),
          (usageRecordId) => [
            UsageAllocation(
              packageId: package.id!,
              usageRecordId: usageRecordId,
              quotaCategoryId: categoryId,
              allocatedBytes: 2 * kBytesPerMB,
              allocationMethod: AllocationMethod.mainFallback,
              createdAt: now,
            ),
          ],
        );
      }

      final breakdown = await breakdownService.build(
        packageId: package.id!,
        now: now,
      );

      expect(breakdown.apps.single.appName, 'Instagram');
    });
  });

  group('Format satuan rincian aplikasi', () {
    test('memakai B, KB, MB, dan GB secara konsisten', () {
      expect(formatUsageBytes(0), '0 B');
      expect(formatUsageBytes(999), '999 B');
      expect(formatUsageBytes(1000), '1,0 KB');
      expect(formatUsageBytes(1500), '1,5 KB');
      expect(formatUsageBytes(950000), '950,0 KB');
      expect(formatUsageBytes(1500000), '1,5 MB');
      expect(formatUsageBytes(25 * kBytesPerMB), '25,0 MB');
      expect(formatUsageBytes(1530000000), '1,53 GB');
    });
  });

  group('UsageBreakdownService - Agregasi per aplikasi', () {
    test('mengelompokkan APP_USAGE dan menghitung persentase', () async {
      setReadings();
      await syncService.syncToday(package);

      final breakdown = await breakdownService.build(
        packageId: package.id!,
        now: now,
      );

      expect(breakdown.apps.length, 2);
      expect(breakdown.apps.first.appName, 'Instagram');
      expect(breakdown.apps.first.totalBytes, 6 * kBytesPerMB);
      expect(breakdown.apps.first.share, closeTo(0.6, 0.001));
      expect(breakdown.apps.last.appName, 'YouTube');
      expect(breakdown.apps.last.share, closeTo(0.4, 0.001));

      expect(breakdown.appTotalBytes, 10 * kBytesPerMB);
      expect(breakdown.deviceTotalBytes, 10 * kBytesPerMB);
      expect(breakdown.differenceBytes, 0);
      expect(breakdown.lastUpdatedAt, isNotNull);
      expect(breakdown.manualMode, false);
    });

    test(
      'selisih agregat perangkat dilaporkan sebagai kualitas data',
      () async {
        setReadings();
        await syncService.syncToday(package);

        // Ubah DEVICE_TOTAL agar berbeda dari jumlah aplikasi.
        final device = (await usageRepo.getRecords(package.id!)).singleWhere(
          (record) => record.recordScope == UsageRecordScope.deviceTotal,
        );

        await usageRepo.upsertRecord(
          device.copyWith(rxBytes: 12 * kBytesPerMB),
        );

        final updated = await breakdownService.build(
          packageId: package.id!,
          now: now,
        );

        expect(updated.differenceBytes, 2 * kBytesPerMB);
      },
    );

    test('mode manual tidak menampilkan rincian aplikasi', () async {
      final categoryId = await mainCategoryId();
      final start = dayStart.add(const Duration(hours: 2));

      await usageRepo.upsertRecordWithAllocations(
        UsageRecord(
          packageId: package.id!,
          recordScope: UsageRecordScope.manualTotal,
          networkType: NetworkType.mobile,
          periodStartAt: start,
          periodEndAt: start.add(const Duration(minutes: 1)),
          rxBytes: 3 * kBytesPerMB,
          txBytes: 0,
          source: UsageSource.manual,
          sourceKey: 'manual_test',
          recordedAt: now,
        ),
        (usageRecordId) => [
          UsageAllocation(
            packageId: package.id!,
            usageRecordId: usageRecordId,
            quotaCategoryId: categoryId,
            allocatedBytes: 3 * kBytesPerMB,
            allocationMethod: AllocationMethod.manualUser,
            createdAt: now,
          ),
        ],
      );

      final breakdown = await breakdownService.build(
        packageId: package.id!,
        now: now,
      );

      expect(breakdown.manualMode, true);
      expect(breakdown.manualTotalBytes, 3 * kBytesPerMB);
      expect(breakdown.apps, isEmpty);
    });

    test('catatan Wi-Fi tidak dihitung sebagai pemakaian seluler', () async {
      await usageRepo.upsertRecord(
        UsageRecord(
          packageId: package.id!,
          recordScope: UsageRecordScope.appUsage,
          appUid: 200,
          appPackageName: 'com.example.wifi',
          appName: 'Wifi App',
          networkType: NetworkType.wifi,
          periodStartAt: bucketStart,
          periodEndAt: bucketEnd,
          rxBytes: 2 * kBytesPerMB,
          txBytes: 0,
          source: UsageSource.android,
          sourceKey: 'wifi_test',
          recordedAt: now,
        ),
      );

      final breakdown = await breakdownService.build(
        packageId: package.id!,
        now: now,
      );

      expect(breakdown.apps, isEmpty);
      expect(breakdown.appTotalBytes, 0);
    });

    test('tanpa catatan menghasilkan breakdown kosong', () async {
      final breakdown = await breakdownService.build(
        packageId: package.id!,
        now: now,
      );

      expect(breakdown.apps, isEmpty);
      expect(breakdown.appTotalBytes, 0);
      expect(breakdown.deviceTotalBytes, 0);
      expect(breakdown.lastUpdatedAt, isNull);
      expect(breakdown.differenceBytes, isNull);
    });
  });
}
