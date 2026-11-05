// MILIK ARSITEK. Versi PALSU (in-memory) untuk minggu 1.
// Minggu 2: diganti implementasi sqflite dengan bentuk yang SAMA.
import '../../models/models.dart';
import '../alert_repository.dart';
import '../package_repository.dart';
import '../settings_repository.dart';
import '../usage_repository.dart';

class InMemoryPackageRepository implements PackageRepository {
  final Map<int, DataPackage> _store = {};
  final List<void Function(int packageId)> _onDelete = [];
  int _nextId = 1;

  /// Dipakai InMemoryUsageRepository untuk meniru ON DELETE CASCADE.
  void addDeleteListener(void Function(int packageId) listener) =>
      _onDelete.add(listener);

  void _deactivateOthers(String userId, int exceptId) {
    for (final e in _store.entries.toList()) {
      if (e.value.userId == userId && e.key != exceptId && e.value.isActive) {
        _store[e.key] = e.value.copyWith(isActive: false);
      }
    }
  }

  @override
  Future<int> add(DataPackage p) async {
    final id = _nextId++;
    if (p.isActive) _deactivateOthers(p.userId, id);
    _store[id] = p.copyWith(id: id);
    return id;
  }

  @override
  Future<void> update(DataPackage p) async {
    final id = p.id;
    if (id == null || !_store.containsKey(id)) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }
    if (p.isActive) _deactivateOthers(p.userId, id);
    _store[id] = p;
  }

  @override
  Future<void> delete(int id) async {
    if (_store.remove(id) == null) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }
    for (final l in _onDelete) {
      l(id);
    }
  }

  @override
  Future<DataPackage?> getById(int id) async => _store[id];

  @override
  Future<DataPackage?> getActive(String userId) async {
    for (final p in await getAll(userId)) {
      if (p.isActive) return p;
    }
    return null;
  }

  @override
  Future<List<DataPackage>> getAll(String userId) async {
    final list = _store.values.where((p) => p.userId == userId).toList()
      ..sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : (b.id ?? 0).compareTo(a.id ?? 0);
      });
    return list;
  }

  @override
  Future<void> setActive(String userId, int packageId) async {
    final target = _store[packageId];
    if (target == null || target.userId != userId) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }
    for (final e in _store.entries.toList()) {
      if (e.value.userId == userId) {
        _store[e.key] = e.value.copyWith(isActive: e.key == packageId);
      }
    }
  }
}

class InMemoryUsageRepository implements UsageRepository {
  InMemoryUsageRepository(this._packages) {
    _packages.addDeleteListener(
        (id) => _records.removeWhere((r) => r.packageId == id));
  }

  final InMemoryPackageRepository _packages;
  final List<UsageRecord> _records = [];

  @override
  Future<void> upsertRecord(
      int packageId, DateTime date, int usedBytes, UsageSource source) async {
    if (usedBytes < 0) {
      throw const AppException(
          AppException.validation, 'Pemakaian tidak boleh negatif.');
    }
    final d = dateOnly(date);
    _records.removeWhere((r) =>
        r.packageId == packageId && r.recordDate == d && r.source == source);
    _records.add(UsageRecord(
      id: _records.length + 1,
      packageId: packageId,
      recordDate: d,
      usedBytes: usedBytes,
      source: source,
      updatedAt: DateTime.now(),
    ));
  }

  @override
  Future<void> deleteManual(int packageId, DateTime date) async {
    final d = dateOnly(date);
    _records.removeWhere((r) =>
        r.packageId == packageId &&
        r.recordDate == d &&
        r.source == UsageSource.manual);
  }

  @override
  Future<List<UsageRecord>> getRecords(int packageId) async =>
      _records.where((r) => r.packageId == packageId).toList();

  @override
  Future<Map<DateTime, int>> getDailyUsage(int packageId) async {
    final byDay = <DateTime, int>{};
    final recs = _records.where((r) => r.packageId == packageId);
    // manual menggantikan auto pada hari yang sama
    for (final r in recs.where((r) => r.source == UsageSource.auto)) {
      byDay[r.recordDate] = r.usedBytes;
    }
    for (final r in recs.where((r) => r.source == UsageSource.manual)) {
      byDay[r.recordDate] = r.usedBytes;
    }
    return byDay;
  }

  @override
  Future<int> getUsedBytesOn(int packageId, DateTime date) async =>
      (await getDailyUsage(packageId))[dateOnly(date)] ?? 0;

  @override
  Future<int> getTotalUsedBytes(int packageId) async {
    final pkg = await _packages.getById(packageId);
    if (pkg == null) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }
    final sum = (await getDailyUsage(packageId)).values.fold<int>(0, (a, b) => a + b);
    return pkg.initialUsedBytes + sum;
  }
}

class InMemoryAlertRepository implements AlertRepository {
  final Set<String> _sent = {};

  String _key(int id, AlertType t, DateTime d) => '$id|${t.name}|${dateToDb(d)}';

  @override
  Future<bool> hasBeenSent(int packageId, AlertType type, DateTime alertDate) async =>
      _sent.contains(_key(packageId, type, alertDate));

  @override
  Future<void> markSent(int packageId, AlertType type, DateTime alertDate) async {
    _sent.add(_key(packageId, type, alertDate));
  }
}

class InMemorySettingsRepository implements SettingsRepository {
  final Map<String, String> _map = {};

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<void> set(String key, String value) async => _map[key] = value;
}
