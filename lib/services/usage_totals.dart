// Aturan pemilihan sumber pemakaian yang dipakai bersama oleh Dashboard dan
// halaman Paket. Tujuannya satu: angka pemakaian tidak boleh berbeda antar
// halaman karena rumus yang berbeda.
import '../models/models.dart';

/// Mengelompokkan catatan pemakaian per tanggal lokal dan memilih satu sumber
/// efektif untuk setiap tanggal.
///
/// Prioritas:
/// 1. MANUAL_TOTAL.
/// 2. DEVICE_TOTAL.
/// 3. APP_USAGE.
///
/// DEVICE_TOTAL dan APP_USAGE tidak pernah dijumlahkan bersamaan, sehingga
/// pemakaian perangkat tidak terhitung dua kali.
Map<DateTime, List<UsageRecord>> effectiveUsageRecordsByDay(
  Iterable<UsageRecord> records,
) {
  final grouped = <DateTime, List<UsageRecord>>{};

  for (final record in records) {
    if (record.networkType == NetworkType.wifi) continue;

    final day = dateOnly(record.periodStartAt);
    grouped.putIfAbsent(day, () => []).add(record);
  }

  final result = <DateTime, List<UsageRecord>>{};

  for (final entry in grouped.entries) {
    final dayRecords = entry.value;

    final manualRecords = dayRecords.where(
      (record) =>
          record.source == UsageSource.manual &&
          record.recordScope == UsageRecordScope.manualTotal,
    );

    final deviceRecords = dayRecords.where(
      (record) =>
          record.source == UsageSource.android &&
          record.recordScope == UsageRecordScope.deviceTotal,
    );

    final appRecords = dayRecords.where(
      (record) =>
          record.source == UsageSource.android &&
          record.recordScope == UsageRecordScope.appUsage,
    );

    final Iterable<UsageRecord> selectedRecords;

    if (manualRecords.isNotEmpty) {
      selectedRecords = manualRecords;
    } else if (deviceRecords.isNotEmpty) {
      selectedRecords = deviceRecords;
    } else {
      selectedRecords = appRecords;
    }

    result[entry.key] = selectedRecords.toList();
  }

  return result;
}

/// Total pemakaian efektif (mobile) dari sekumpulan catatan.
int totalEffectiveUsageBytes(Iterable<UsageRecord> records) {
  var total = 0;

  for (final dayRecords in effectiveUsageRecordsByDay(records).values) {
    for (final record in dayRecords) {
      total += record.totalBytes;
    }
  }

  return total;
}
