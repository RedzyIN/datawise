import '../models/models.dart';

abstract class AlertRepository {
  Future<String> add(AlertLog alert);

  /// Menyimpan alert hanya jika [AlertLog.dedupeKey] belum pernah tersimpan.
  ///
  /// Mengembalikan id alert baru, atau `null` bila alert dengan dedupe key yang
  /// sama sudah ada. Implementasi SQLite mengandalkan UNIQUE(dedupe_key)
  /// sehingga dua evaluasi yang berjalan hampir bersamaan tetap aman.
  Future<String?> createIfAbsent(AlertLog alert);

  Future<bool> existsByDedupeKey(String dedupeKey);

  Future<List<AlertLog>> getByPackage(String packageId);

  Future<void> markRead(String alertId);

  Future<void> markAllRead(String packageId);

  /// Menghapus satu alert.
  ///
  /// Dipakai sebagai mekanisme pemulihan ketika penyimpanan berhasil tetapi
  /// notifikasi gagal ditampilkan: alert tidak boleh dianggap sudah diproses
  /// secara permanen sehingga evaluasi berikutnya dapat mencoba lagi.
  Future<void> delete(String alertId);
}
