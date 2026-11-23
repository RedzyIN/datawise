// Menyambungkan pembacaan Android dengan penyimpanan SQLite.
//
// Kanal Android hanya menyediakan total pemakaian perangkat (agregat), bukan
// rincian per aplikasi. Karena itu hasil pembacaan disimpan sebagai catatan
// DEVICE_TOTAL: catatan ini tidak boleh dan tidak dapat dialokasikan ke
// kategori kuota (lihat trigger `prevent_invalid_allocation_*` pada skema v3).
// Dengan begitu sistem tidak mengarang klasifikasi yang tidak diketahui.
//
// Sinkronisasi rincian per aplikasi (fitur minggu 3) berada di
// `app_usage_sync_service.dart` agar tidak menjadi ketergantungan fitur
// minggu 1 dan 2.
import '../models/models.dart';
import '../repositories/repositories.dart';
import 'usage_service.dart';

enum UsageSyncStatus { saved, permissionDenied, unsupported, error }

class UsageSyncResult {
  const UsageSyncResult({
    required this.status,
    this.reading,
    this.record,
    this.message,
  });

  final UsageSyncStatus status;
  final UsageReading? reading;

  /// Catatan yang benar-benar tersimpan di repository (null jika tidak ada).
  final UsageRecord? record;
  final String? message;

  bool get saved => status == UsageSyncStatus.saved;
}

abstract class UsageSyncService {
  Future<bool> hasPermission();

  Future<void> openUsageAccessSettings();

  /// Membaca pemakaian hari ini lalu menyimpan/memperbarui catatan SQLite.
  Future<UsageSyncResult> syncToday(DataPackage package);
}

class UsageSyncServiceImpl implements UsageSyncService {
  UsageSyncServiceImpl(this._service, this._usageRepo);

  final UsageService _service;
  final UsageRepository _usageRepo;

  /// Identitas periode pembacaan. Satu hari, satu paket, satu catatan.
  ///
  /// Pembacaan berulang pada hari yang sama memperbarui baris yang sama
  /// sehingga tidak terjadi duplikasi.
  static String sourceKeyFor(String packageId, DateTime day) =>
      'android_device_total_${packageId}_${dateToDb(day)}';

  @override
  Future<bool> hasPermission() => _service.hasPermission();

  @override
  Future<void> openUsageAccessSettings() => _service.openUsageAccessSettings();

  UsageSyncStatus _statusFrom(UsageReadStatus status) => switch (status) {
    UsageReadStatus.ok => UsageSyncStatus.saved,
    UsageReadStatus.permissionDenied => UsageSyncStatus.permissionDenied,
    UsageReadStatus.unsupported => UsageSyncStatus.unsupported,
    UsageReadStatus.error => UsageSyncStatus.error,
  };

  @override
  Future<UsageSyncResult> syncToday(DataPackage package) async {
    final packageId = package.id;

    if (packageId == null) {
      return const UsageSyncResult(
        status: UsageSyncStatus.error,
        message: 'Paket belum memiliki ID.',
      );
    }

    final reading = await _service.refreshToday(package);

    if (reading.status != UsageReadStatus.ok) {
      return UsageSyncResult(
        status: _statusFrom(reading.status),
        reading: reading,
        message: reading.message,
      );
    }

    // Pembacaan ok tetapi nilainya negatif tidak mungkin berasal dari Android.
    if (reading.totalBytes < 0) {
      return UsageSyncResult(
        status: UsageSyncStatus.error,
        reading: reading,
        message: 'Android mengembalikan nilai pemakaian yang tidak valid.',
      );
    }

    final now = DateTime.now();
    final start = dateOnly(now);
    final end = now.isAfter(start)
        ? now
        : start.add(const Duration(seconds: 1));

    final record = UsageRecord(
      packageId: packageId,
      recordScope: UsageRecordScope.deviceTotal,
      networkType: NetworkType.mobile,
      periodStartAt: start,
      periodEndAt: end,
      // Nilai dari NetworkStatsManager sudah merupakan RX + TX.
      rxBytes: reading.totalBytes,
      txBytes: 0,
      source: UsageSource.android,
      sourceKey: sourceKeyFor(packageId, start),
      recordedAt: now,
    );

    try {
      final id = await _usageRepo.upsertRecord(record);

      return UsageSyncResult(
        status: UsageSyncStatus.saved,
        reading: reading,
        record: record.copyWith(id: id),
      );
    } on AppException catch (e) {
      return UsageSyncResult(
        status: UsageSyncStatus.error,
        reading: reading,
        message: e.message,
      );
    } catch (e) {
      return UsageSyncResult(
        status: UsageSyncStatus.error,
        reading: reading,
        message: 'Gagal menyimpan pemakaian perangkat: $e',
      );
    }
  }
}
