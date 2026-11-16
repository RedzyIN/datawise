import '../models/models.dart';

abstract class PackageRepository {
  /// [initialUsedBytes] > 0 membuat catatan pemakaian awal (MANUAL_TOTAL)
  /// yang dialokasikan ke kategori utama, dalam satu transaksi dengan paket.
  Future<String> add(DataPackage package, {int initialUsedBytes = 0});

  Future<void> update(DataPackage package);

  /// Melempar AppException jika paket sudah memiliki riwayat pemakaian.
  Future<void> delete(String packageId);

  Future<bool> hasUsageHistory(String packageId);

  Future<DataPackage?> getById(String packageId);
  Future<DataPackage?> getActive(String userId);
  Future<List<DataPackage>> getAll(String userId);

  /// Menjamin hanya satu paket ACTIVE per pengguna.
  Future<void> setActive(String userId, String packageId);

  /// Mengubah paket ACTIVE/INACTIVE yang sudah lewat tanggal berakhir
  /// menjadi EXPIRED. Mengembalikan jumlah paket yang diubah.
  Future<int> markExpired(String userId);
}
