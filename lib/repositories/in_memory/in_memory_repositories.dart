import '../../models/models.dart';
import '../alert_repository.dart';
import '../classification_rule_repository.dart';
import '../data_limit_repository.dart';
import '../package_repository.dart';
import '../quota_category_repository.dart';
import '../settings_repository.dart';
import '../usage_repository.dart';
import '../user_repository.dart';

String _memoryId(String prefix, int number) => '${prefix}_$number';

class InMemoryUserRepository implements UserRepository {
  final Map<String, AppUser> items = {};

  @override
  Future<void> upsert(AppUser user) async {
    final uid = user.uid.trim();
    if (uid.isEmpty) {
      throw const AppException(
        AppException.validation,
        'UID pengguna wajib tersedia.',
      );
    }

    items[uid] = AppUser(
      uid: uid,
      displayName: user.displayName?.trim().isEmpty == true
          ? null
          : user.displayName?.trim(),
      email: user.email?.trim().isEmpty == true ? null : user.email?.trim(),
    );
  }

  @override
  Future<AppUser?> getById(String uid) async => items[uid];
}

class InMemoryPackageRepository implements PackageRepository {
  final Map<String, DataPackage> _items = {};
  final Map<String, int> initialUsage = {};
  final List<void Function(String)> _deleteListeners = [];
  final List<bool Function(String)> _deleteGuards = [];
  final List<void Function(DataPackage, List<QuotaCategory>)> _addListeners =
      [];
  final List<void Function(DataPackage, DataPackage)> _updateListeners = [];

  int _nextId = 1;

  void addDeleteListener(void Function(String) listener) {
    _deleteListeners.add(listener);
  }

  /// Guard mengembalikan false jika paket tidak boleh dihapus (punya riwayat).
  void addDeleteGuard(bool Function(String packageId) guard) {
    _deleteGuards.add(guard);
  }

  void addAddListener(
    void Function(DataPackage, List<QuotaCategory>) listener,
  ) {
    _addListeners.add(listener);
  }

  void addUpdateListener(void Function(DataPackage, DataPackage) listener) {
    _updateListeners.add(listener);
  }

  final List<Object? Function()> _participantSnapshots = [];
  final List<void Function(Object? state)> _participantRestorers = [];

  /// Mendaftarkan repository lain yang ikut berubah saat paket disimpan
  /// (misalnya kategori kuota) supaya ikut di-rollback bila operasi gagal.
  void addTransactionParticipant({
    required Object? Function() snapshot,
    required void Function(Object? state) restore,
  }) {
    _participantSnapshots.add(snapshot);
    _participantRestorers.add(restore);
  }

  List<Object?> _takeParticipantSnapshots() => [
    for (final snapshot in _participantSnapshots) snapshot(),
  ];

  void _rollbackParticipants(List<Object?> snapshots) {
    for (var i = 0; i < _participantRestorers.length; i++) {
      _participantRestorers[i](snapshots[i]);
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _deactivate(String userId, String exceptId) {
    for (final entry in _items.entries.toList()) {
      if (entry.value.userId == userId &&
          entry.key != exceptId &&
          entry.value.status == PackageStatus.active) {
        _items[entry.key] = entry.value.copyWith(
          status: PackageStatus.inactive,
        );
      }
    }
  }

  void _validate(DataPackage package) {
    if (package.userId.trim().isEmpty ||
        package.packageName.trim().isEmpty ||
        package.advertisedTotalQuotaBytes <= 0 ||
        package.endDate.isBefore(package.startDate) ||
        (package.status == PackageStatus.active &&
            _dateOnly(package.endDate).isBefore(_dateOnly(DateTime.now())))) {
      throw const AppException(
        AppException.validation,
        'Data paket tidak valid atau masa aktif paket sudah berakhir.',
      );
    }
  }

  @override
  Future<String> add(DataPackage package, {int initialUsedBytes = 0}) {
    return addWithCategories(package, initialUsedBytes: initialUsedBytes);
  }

  @override
  Future<String> addWithCategories(
    DataPackage package, {
    List<QuotaCategory> categories = const [],
    int initialUsedBytes = 0,
  }) async {
    _validate(package);

    if (initialUsedBytes < 0 ||
        initialUsedBytes > package.advertisedTotalQuotaBytes) {
      throw const AppException(
        AppException.validation,
        'Kuota terpakai tidak boleh melebihi total kuota.',
      );
    }

    var additionalBytes = 0;
    for (final category in categories) {
      if (category.categoryType == QuotaCategoryType.main ||
          category.categoryName.trim().isEmpty ||
          category.capacityBytes <= 0 ||
          (category.validFrom != null &&
              category.validUntil != null &&
              category.validUntil!.isBefore(category.validFrom!))) {
        throw const AppException(
          AppException.validation,
          'Data kategori tidak valid.',
        );
      }
      additionalBytes += category.capacityBytes;
    }

    if (additionalBytes >= package.advertisedTotalQuotaBytes) {
      throw const AppException(
        AppException.validation,
        'Total kuota tidak cukup untuk menampung kategori tambahan.',
      );
    }

    final id = package.id ?? _memoryId('package', _nextId++);

    final saved = package.copyWith(
      id: id,
      packageName: package.packageName.trim(),
      operatorName: package.operatorName?.trim().isEmpty == true
          ? null
          : package.operatorName?.trim(),
    );

    // Snapshot seluruh state yang dapat berubah selama operasi. Rollback harus
    // mengembalikan paket, initial usage, status paket aktif sebelumnya, dan
    // state repository lain yang berpartisipasi (kategori kuota).
    final packageSnapshot = Map<String, DataPackage>.of(_items);
    final usageSnapshot = Map<String, int>.of(initialUsage);
    final participantSnapshots = _takeParticipantSnapshots();

    if (saved.status == PackageStatus.active) {
      _deactivate(saved.userId, id);
    }

    _items[id] = saved;
    if (initialUsedBytes > 0) initialUsage[id] = initialUsedBytes;

    try {
      for (final listener in _addListeners) {
        listener(saved, categories);
      }
    } catch (_) {
      _items
        ..clear()
        ..addAll(packageSnapshot);
      initialUsage
        ..clear()
        ..addAll(usageSnapshot);
      _rollbackParticipants(participantSnapshots);
      rethrow;
    }

    return id;
  }

  @override
  Future<void> update(DataPackage package) async {
    final id = package.id;

    if (id == null || !_items.containsKey(id)) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    _validate(package);

    final oldPackage = _items[id]!;

    if (oldPackage.userId != package.userId) {
      throw const AppException(
        AppException.validation,
        'Pemilik paket tidak boleh diubah.',
      );
    }

    final storedPackage = package.copyWith(
      packageName: package.packageName.trim(),
      operatorName: package.operatorName?.trim().isEmpty == true
          ? null
          : package.operatorName?.trim(),
      createdAt: oldPackage.createdAt,
    );

    final packageSnapshot = Map<String, DataPackage>.of(_items);
    final participantSnapshots = _takeParticipantSnapshots();

    try {
      for (final listener in _updateListeners) {
        listener(oldPackage, storedPackage);
      }

      if (storedPackage.status == PackageStatus.active) {
        _deactivate(storedPackage.userId, id);
      }

      _items[id] = storedPackage;
    } catch (_) {
      _items
        ..clear()
        ..addAll(packageSnapshot);
      _rollbackParticipants(participantSnapshots);
      rethrow;
    }
  }

  @override
  Future<bool> hasUsageHistory(String packageId) async {
    return (initialUsage[packageId] ?? 0) > 0 ||
        _deleteGuards.any((guard) => !guard(packageId));
  }

  @override
  Future<void> delete(String packageId) async {
    if (!_items.containsKey(packageId)) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    if (await hasUsageHistory(packageId)) {
      throw const AppException(
        AppException.validation,
        'Paket yang sudah memiliki riwayat pemakaian tidak dapat dihapus. '
        'Arsipkan paket ini sebagai gantinya.',
      );
    }

    _items.remove(packageId);
    initialUsage.remove(packageId);

    for (final listener in _deleteListeners) {
      listener(packageId);
    }
  }

  @override
  Future<DataPackage?> getById(String packageId) async => _items[packageId];

  @override
  Future<DataPackage?> getActive(String userId) async {
    return _items.values
        .where((p) => p.userId == userId && p.status == PackageStatus.active)
        .firstOrNull;
  }

  @override
  Future<List<DataPackage>> getAll(String userId) async {
    final result = _items.values
        .where((package) => package.userId == userId)
        .toList();

    result.sort((a, b) {
      final comparison = b.createdAt.compareTo(a.createdAt);
      return comparison != 0 ? comparison : (b.id ?? '').compareTo(a.id ?? '');
    });

    return result;
  }

  @override
  Future<void> setActive(String userId, String packageId) async {
    final package = _items[packageId];

    if (package == null || package.userId != userId) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    if (package.status == PackageStatus.expired ||
        package.status == PackageStatus.archived ||
        _dateOnly(package.endDate).isBefore(_dateOnly(DateTime.now()))) {
      throw const AppException(
        AppException.validation,
        'Paket yang sudah kedaluwarsa atau diarsipkan tidak dapat diaktifkan.',
      );
    }

    for (final entry in _items.entries.toList()) {
      if (entry.value.userId != userId) continue;

      if (entry.key == packageId) {
        _items[entry.key] = entry.value.copyWith(status: PackageStatus.active);
      } else if (entry.value.status == PackageStatus.active) {
        _items[entry.key] = entry.value.copyWith(
          status: PackageStatus.inactive,
        );
      }
    }
  }

  @override
  Future<int> markExpired(String userId) async {
    final today = _dateOnly(DateTime.now());
    var count = 0;

    for (final entry in _items.entries.toList()) {
      final p = entry.value;
      if (p.userId == userId &&
          (p.status == PackageStatus.active ||
              p.status == PackageStatus.inactive) &&
          _dateOnly(p.endDate).isBefore(today)) {
        _items[entry.key] = p.copyWith(status: PackageStatus.expired);
        count++;
      }
    }

    return count;
  }
}

class InMemoryQuotaCategoryRepository implements QuotaCategoryRepository {
  InMemoryQuotaCategoryRepository(this.packages) {
    packages.addAddListener(_createMainCategory);
    packages.addUpdateListener(_handlePackageUpdate);
    packages.addDeleteListener(_handlePackageDelete);
    packages.addTransactionParticipant(
      snapshot: () => Map<String, QuotaCategory>.of(items),
      restore: (state) {
        items
          ..clear()
          ..addAll(state as Map<String, QuotaCategory>);
      },
    );

    // Also handle packages created before this repository was constructed.
    for (final package in packages._items.values) {
      _createMainCategory(package, const []);
    }
  }

  final InMemoryPackageRepository packages;
  final Map<String, QuotaCategory> items = {};
  final List<void Function(String)> _deleteListeners = [];
  final List<bool Function(String)> _deleteGuards = [];

  int _nextId = 1;

  void addDeleteListener(void Function(String) listener) {
    _deleteListeners.add(listener);
  }

  void addDeleteGuard(bool Function(String) guard) {
    _deleteGuards.add(guard);
  }

  /// Validasi yang sama dengan [SqliteQuotaCategoryRepository]: nama wajib,
  /// kapasitas positif, dan rentang tanggal tidak terbalik bila keduanya ada.
  void _validateCategory(QuotaCategory category) {
    if (category.categoryName.trim().isEmpty ||
        category.capacityBytes <= 0 ||
        (category.validFrom != null &&
            category.validUntil != null &&
            category.validUntil!.isBefore(category.validFrom!))) {
      throw const AppException(
        AppException.validation,
        'Data kategori tidak valid.',
      );
    }
  }

  void _createMainCategory(
    DataPackage package,
    List<QuotaCategory> additional,
  ) {
    final packageId = package.id!;
    var mainCapacity = package.advertisedTotalQuotaBytes;

    for (final category in additional) {
      mainCapacity -= category.capacityBytes;
    }

    final mainId = _memoryId('category', _nextId++);

    items[mainId] = QuotaCategory(
      id: mainId,
      packageId: packageId,
      categoryName: 'Kuota Utama',
      categoryType: QuotaCategoryType.main,
      capacityBytes: mainCapacity,
      validFrom: package.startDate,
      validUntil: package.endDate,
      isEnabled: true,
      createdAt: package.createdAt,
    );

    for (final category in additional) {
      final id = category.id ?? _memoryId('category', _nextId++);

      items[id] = category.copyWith(id: id, packageId: packageId);
    }
  }

  void _handlePackageUpdate(DataPackage oldPackage, DataPackage newPackage) {
    final main = items.values
        .where(
          (category) =>
              category.packageId == oldPackage.id &&
              category.categoryType == QuotaCategoryType.main,
        )
        .firstOrNull;

    if (main == null) return;

    final difference =
        newPackage.advertisedTotalQuotaBytes -
        oldPackage.advertisedTotalQuotaBytes;

    final nextCapacity = main.capacityBytes + difference;

    if (nextCapacity <= 0) {
      throw const AppException(
        AppException.validation,
        'Total kuota paket tidak mencukupi untuk mempertahankan kategori.',
      );
    }

    items[main.id!] = main.copyWith(
      capacityBytes: nextCapacity,
      validFrom: newPackage.startDate,
      validUntil: newPackage.endDate,
    );
  }

  void _handlePackageDelete(String packageId) {
    final categoryIds = items.values
        .where((category) => category.packageId == packageId)
        .map((category) => category.id!)
        .toSet();

    items.removeWhere((_, category) => category.packageId == packageId);

    for (final id in categoryIds) {
      for (final listener in _deleteListeners) {
        listener(id);
      }
    }
  }

  @override
  Future<String> add(QuotaCategory category) async {
    _validateCategory(category);

    if (category.categoryType == QuotaCategoryType.main) {
      throw const AppException(
        AppException.validation,
        'Data kategori tidak valid.',
      );
    }

    final main = items.values
        .where(
          (item) =>
              item.packageId == category.packageId &&
              item.categoryType == QuotaCategoryType.main,
        )
        .firstOrNull;

    if (main == null) {
      throw const AppException(
        AppException.notFound,
        'Kategori utama paket tidak ditemukan.',
      );
    }

    if (category.capacityBytes >= main.capacityBytes) {
      throw const AppException(
        AppException.validation,
        'Sisa kuota utama tidak mencukupi.',
      );
    }

    final id = category.id ?? _memoryId('category', _nextId++);

    items[main.id!] = main.copyWith(
      capacityBytes: main.capacityBytes - category.capacityBytes,
    );

    items[id] = category.copyWith(id: id);

    return id;
  }

  @override
  Future<void> update(QuotaCategory category) async {
    final id = category.id;

    if (id == null || !items.containsKey(id)) {
      throw const AppException(
        AppException.notFound,
        'Kategori tidak ditemukan.',
      );
    }

    _validateCategory(category);

    final old = items[id]!;

    if (old.packageId != category.packageId ||
        old.categoryType != category.categoryType) {
      throw const AppException(
        AppException.validation,
        'Paket dan jenis kategori tidak boleh diubah.',
      );
    }

    if (old.categoryType == QuotaCategoryType.main) {
      throw const AppException(
        AppException.validation,
        'Kuota kategori utama diatur otomatis.',
      );
    }

    final main = items.values
        .where(
          (item) =>
              item.packageId == category.packageId &&
              item.categoryType == QuotaCategoryType.main,
        )
        .firstOrNull;

    if (main == null) {
      throw const AppException(
        AppException.notFound,
        'Kategori utama tidak ditemukan.',
      );
    }

    final nextMainCapacity =
        main.capacityBytes + old.capacityBytes - category.capacityBytes;

    if (nextMainCapacity <= 0) {
      throw const AppException(
        AppException.validation,
        'Sisa kuota utama tidak mencukupi.',
      );
    }

    items[id] = category;
    items[main.id!] = main.copyWith(capacityBytes: nextMainCapacity);
  }

  @override
  Future<void> delete(String categoryId) async {
    final category = items[categoryId];

    if (category == null) {
      throw const AppException(
        AppException.notFound,
        'Kategori tidak ditemukan.',
      );
    }

    if (category.categoryType == QuotaCategoryType.main) {
      throw const AppException(
        AppException.validation,
        'Kategori utama tidak boleh dihapus.',
      );
    }

    if (_deleteGuards.any((guard) => !guard(categoryId))) {
      throw const AppException(
        AppException.validation,
        'Kategori masih digunakan oleh aturan klasifikasi atau alokasi penggunaan.',
      );
    }

    final main = items.values
        .where(
          (item) =>
              item.packageId == category.packageId &&
              item.categoryType == QuotaCategoryType.main,
        )
        .firstOrNull;

    if (main == null) {
      throw const AppException(
        AppException.notFound,
        'Kategori utama tidak ditemukan.',
      );
    }

    items.remove(categoryId);

    items[main.id!] = main.copyWith(
      capacityBytes: main.capacityBytes + category.capacityBytes,
    );

    for (final listener in _deleteListeners) {
      listener(categoryId);
    }
  }

  @override
  Future<QuotaCategory?> getById(String categoryId) async {
    return items[categoryId];
  }

  @override
  Future<List<QuotaCategory>> getByPackage(String packageId) async {
    final result = items.values
        .where((category) => category.packageId == packageId)
        .toList();

    result.sort((a, b) {
      if (a.categoryType == QuotaCategoryType.main) return -1;
      if (b.categoryType == QuotaCategoryType.main) return 1;
      return (a.id ?? '').compareTo(b.id ?? '');
    });

    return result;
  }
}

class InMemoryClassificationRuleRepository
    implements ClassificationRuleRepository {
  InMemoryClassificationRuleRepository(this.packages, this.categories) {
    packages.addDeleteListener(_handlePackageDelete);
    categories.addDeleteListener(_handleCategoryDelete);
    categories.addDeleteGuard(
      (categoryId) =>
          !items.values.any((rule) => rule.quotaCategoryId == categoryId),
    );
  }

  final InMemoryPackageRepository packages;
  final InMemoryQuotaCategoryRepository categories;
  final Map<String, ClassificationRule> items = {};

  int _nextId = 1;

  void _handlePackageDelete(String packageId) {
    items.removeWhere((_, rule) {
      final category = categories.items[rule.quotaCategoryId];
      return category == null || category.packageId == packageId;
    });
  }

  void _handleCategoryDelete(String categoryId) {
    items.removeWhere((_, rule) => rule.quotaCategoryId == categoryId);
  }

  void _validate(ClassificationRule rule) {
    final appName = rule.appPackageName;

    if (rule.ruleName.trim().isEmpty ||
        (appName != null && appName.trim().isEmpty) ||
        ((rule.startMinute == null) != (rule.endMinute == null)) ||
        (rule.startMinute != null &&
            (rule.startMinute! < 0 || rule.startMinute! > 1439)) ||
        (rule.endMinute != null &&
            (rule.endMinute! < 0 || rule.endMinute! > 1440)) ||
        rule.daysOfWeekMask < 1 ||
        rule.daysOfWeekMask > 127 ||
        rule.priority < 0) {
      throw const AppException(
        AppException.validation,
        'Aturan klasifikasi tidak valid.',
      );
    }
  }

  @override
  Future<String> add(ClassificationRule rule) async {
    _validate(rule);

    final category = await categories.getById(rule.quotaCategoryId);

    if (category == null) {
      throw const AppException(
        AppException.notFound,
        'Kategori aturan tidak ditemukan.',
      );
    }

    final id = rule.id ?? _memoryId('rule', _nextId++);

    items[id] = ClassificationRule(
      id: id,
      quotaCategoryId: rule.quotaCategoryId,
      ruleName: rule.ruleName,
      appPackageName: rule.appPackageName,
      startMinute: rule.startMinute,
      endMinute: rule.endMinute,
      daysOfWeekMask: rule.daysOfWeekMask,
      priority: rule.priority,
      isEnabled: rule.isEnabled,
      createdAt: rule.createdAt,
    );

    return id;
  }

  @override
  Future<void> update(ClassificationRule rule) async {
    final id = rule.id;

    if (id == null || !items.containsKey(id)) {
      throw const AppException(
        AppException.notFound,
        'Aturan klasifikasi tidak ditemukan.',
      );
    }

    _validate(rule);

    final category = await categories.getById(rule.quotaCategoryId);

    if (category == null) {
      throw const AppException(
        AppException.notFound,
        'Kategori aturan tidak ditemukan.',
      );
    }

    items[id] = rule;
  }

  @override
  Future<void> delete(String ruleId) async {
    if (items.remove(ruleId) == null) {
      throw const AppException(
        AppException.notFound,
        'Aturan klasifikasi tidak ditemukan.',
      );
    }
  }

  @override
  Future<List<ClassificationRule>> getByPackage(String packageId) async {
    final result = items.values.where((rule) {
      final category = categories.items[rule.quotaCategoryId];
      return category?.packageId == packageId;
    }).toList();

    result.sort((a, b) {
      final priorityComparison = b.priority.compareTo(a.priority);
      if (priorityComparison != 0) return priorityComparison;

      final specificityComparison = (a.appPackageName == null ? 1 : 0)
          .compareTo(b.appPackageName == null ? 1 : 0);
      if (specificityComparison != 0) return specificityComparison;

      return (a.id ?? '').compareTo(b.id ?? '');
    });

    return result;
  }
}

class InMemoryUsageRepository implements UsageRepository {
  InMemoryUsageRepository(this.packages, [this.categories, this.rules]) {
    packages.addDeleteListener(_handlePackageDelete);
    packages.addDeleteGuard(
      (packageId) => !records.values.any((r) => r.packageId == packageId),
    );
    categories?.addDeleteListener(_handleCategoryDelete);
    categories?.addDeleteGuard(
      (categoryId) => !allocations.values.any(
        (allocation) => allocation.quotaCategoryId == categoryId,
      ),
    );
  }

  final InMemoryPackageRepository packages;
  final InMemoryQuotaCategoryRepository? categories;
  final InMemoryClassificationRuleRepository? rules;

  final Map<String, UsageRecord> records = {};
  final Map<String, UsageAllocation> allocations = {};

  int _nextRecordId = 1;
  int _nextAllocationId = 1;

  void _handlePackageDelete(String packageId) {
    final recordIds = records.values
        .where((record) => record.packageId == packageId)
        .map((record) => record.id!)
        .toSet();

    records.removeWhere((_, record) => record.packageId == packageId);

    allocations.removeWhere(
      (_, allocation) => recordIds.contains(allocation.usageRecordId),
    );
  }

  void _handleCategoryDelete(String categoryId) {
    allocations.removeWhere(
      (_, allocation) => allocation.quotaCategoryId == categoryId,
    );
  }

  void _validateRecord(UsageRecord record) {
    if (record.rxBytes < 0 ||
        record.txBytes < 0 ||
        !record.periodEndAt.isAfter(record.periodStartAt) ||
        ((record.source == UsageSource.manual) !=
            (record.recordScope == UsageRecordScope.manualTotal))) {
      throw const AppException(
        AppException.validation,
        'Data pemakaian tidak valid.',
      );
    }
    if (record.recordScope == UsageRecordScope.appUsage &&
        (record.appPackageName == null ||
            record.appPackageName!.trim().isEmpty)) {
      throw const AppException(
        AppException.validation,
        'Nama paket aplikasi wajib diisi untuk catatan pemakaian aplikasi.',
      );
    }
  }

  Future<String?> _matchingRecordId(UsageRecord record) async {
    final matching = record.sourceKey == null
        ? null
        : records.values
              .where((item) => item.sourceKey == record.sourceKey)
              .firstOrNull;
    if (matching != null &&
        (matching.packageId != record.packageId ||
            (record.id != null && record.id != matching.id))) {
      throw const AppException(
        AppException.validation,
        'Source key tidak boleh digunakan oleh catatan atau paket lain.',
      );
    }

    final existingId = record.id ?? matching?.id;
    if (existingId != null) {
      final existing = records[existingId];
      if (existing != null && existing.packageId != record.packageId) {
        throw const AppException(
          AppException.validation,
          'Catatan pemakaian tidak dapat dipindahkan ke paket lain.',
        );
      }
    }
    return existingId;
  }

  @override
  Future<String> upsertRecord(UsageRecord record) async {
    _validateRecord(record);
    final chargeable =
        record.networkType != NetworkType.wifi &&
        (record.recordScope == UsageRecordScope.appUsage ||
            record.recordScope == UsageRecordScope.manualTotal);
    if (chargeable) {
      throw const AppException(
        AppException.validation,
        'Catatan penggunaan ini harus disimpan bersama alokasinya.',
      );
    }
    if (await packages.getById(record.packageId) == null) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }
    final existingId = await _matchingRecordId(record);
    final id = existingId ?? _memoryId('usage', _nextRecordId++);
    records[id] = record.copyWith(id: id);
    return id;
  }

  @override
  Future<String> upsertRecordWithAllocations(
    UsageRecord record,
    List<UsageAllocation> Function(String usageRecordId) allocationBuilder,
  ) async {
    _validateRecord(record);
    if (record.recordScope == UsageRecordScope.deviceTotal ||
        record.networkType == NetworkType.wifi) {
      throw const AppException(
        AppException.validation,
        'Catatan agregat perangkat atau Wi-Fi tidak dapat dialokasikan.',
      );
    }
    if (await packages.getById(record.packageId) == null) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    final existingId = await _matchingRecordId(record);
    final id = existingId ?? _memoryId('usage', _nextRecordId++);
    final saved = record.copyWith(id: id);
    final rows = allocationBuilder(id);
    await _validateAndSaveAllocations(saved, id, rows);
    records[id] = saved;
    return id;
  }

  @override
  Future<void> deleteManualRecords(
    String packageId,
    DateTime periodStartAt,
    DateTime periodEndAt,
  ) async {
    final ids = records.values
        .where(
          (record) =>
              record.packageId == packageId &&
              record.source == UsageSource.manual &&
              record.recordScope == UsageRecordScope.manualTotal &&
              !record.periodStartAt.isBefore(periodStartAt) &&
              !record.periodEndAt.isAfter(periodEndAt),
        )
        .map((record) => record.id!)
        .toSet();

    records.removeWhere((_, record) => ids.contains(record.id));

    allocations.removeWhere(
      (_, allocation) => ids.contains(allocation.usageRecordId),
    );
  }

  @override
  Future<UsageRecord?> getById(String recordId) async {
    return records[recordId];
  }

  @override
  Future<List<UsageRecord>> getRecords(String packageId) async {
    final result = records.values
        .where((record) => record.packageId == packageId)
        .toList();

    result.sort((a, b) => a.periodStartAt.compareTo(b.periodStartAt));

    return result;
  }

  @override
  Future<List<UsageRecord>> getRecordsForPeriod(
    String packageId,
    DateTime startAt,
    DateTime endAt,
  ) async {
    final result = records.values
        .where(
          (record) =>
              record.packageId == packageId &&
              record.periodStartAt.isBefore(endAt) &&
              record.periodEndAt.isAfter(startAt),
        )
        .toList();

    result.sort((a, b) => a.periodStartAt.compareTo(b.periodStartAt));

    return result;
  }

  Future<void> _validateAndSaveAllocations(
    UsageRecord record,
    String usageRecordId,
    List<UsageAllocation> rows,
  ) async {
    if ((record.recordScope != UsageRecordScope.appUsage &&
            record.recordScope != UsageRecordScope.manualTotal) ||
        record.networkType == NetworkType.wifi) {
      throw const AppException(
        AppException.validation,
        'Catatan pemakaian ini tidak dapat memiliki alokasi kategori.',
      );
    }

    final total = rows.fold<int>(0, (sum, item) => sum + item.allocatedBytes);
    if (rows.any((item) => item.allocatedBytes < 0) ||
        total != record.totalBytes) {
      throw const AppException(
        AppException.validation,
        'Total alokasi harus sama persis dengan RX + TX catatan pemakaian.',
      );
    }

    for (final item in rows) {
      if (item.packageId != record.packageId ||
          item.usageRecordId != usageRecordId) {
        throw const AppException(
          AppException.validation,
          'Alokasi tidak sesuai dengan catatan pemakaian.',
        );
      }
      final method = item.allocationMethod;
      final categoryId = item.quotaCategoryId;
      final ruleId = item.classificationRuleId;

      if ((method == AllocationMethod.unclassified &&
              (categoryId != null || ruleId != null)) ||
          (method != AllocationMethod.unclassified && categoryId == null) ||
          ((method == AllocationMethod.autoRule) != (ruleId != null))) {
        throw const AppException(
          AppException.validation,
          'Kombinasi metode, kategori, dan aturan alokasi tidak valid.',
        );
      }

      if ((method == AllocationMethod.autoRule ||
              method == AllocationMethod.mainFallback) &&
          (record.recordScope != UsageRecordScope.appUsage ||
              record.source != UsageSource.android)) {
        throw const AppException(
          AppException.validation,
          'Klasifikasi otomatis hanya berlaku untuk APP_USAGE Android.',
        );
      }

      QuotaCategory? category;
      if (categoryId != null) {
        if (categories == null) {
          throw const AppException(
            AppException.validation,
            'Repository kategori diperlukan untuk memvalidasi alokasi.',
          );
        }
        category = await categories!.getById(categoryId);
        if (category == null ||
            category.packageId != record.packageId ||
            !category.isEnabled) {
          throw const AppException(
            AppException.validation,
            'Kategori tidak tersedia atau bukan milik paket ini.',
          );
        }
      }

      if (method == AllocationMethod.mainFallback &&
          category?.categoryType != QuotaCategoryType.main) {
        throw const AppException(
          AppException.validation,
          'MAIN_FALLBACK harus mengarah ke kategori MAIN.',
        );
      }

      if (ruleId != null) {
        if (rules == null) {
          throw const AppException(
            AppException.validation,
            'Repository aturan diperlukan untuk memvalidasi AUTO_RULE.',
          );
        }
        final ruleRows = await rules!.getByPackage(record.packageId);
        final rule = ruleRows
            .where((candidate) => candidate.id == ruleId)
            .firstOrNull;
        if (rule == null ||
            !rule.isEnabled ||
            rule.quotaCategoryId != categoryId) {
          throw const AppException(
            AppException.validation,
            'Aturan klasifikasi tidak aktif atau tidak sesuai kategori.',
          );
        }
      }
    }

    allocations.removeWhere((_, item) => item.usageRecordId == usageRecordId);
    for (final item in rows) {
      final id = item.id ?? _memoryId('allocation', _nextAllocationId++);
      allocations[id] = UsageAllocation(
        id: id,
        packageId: item.packageId,
        usageRecordId: item.usageRecordId,
        quotaCategoryId: item.quotaCategoryId,
        classificationRuleId: item.classificationRuleId,
        allocatedBytes: item.allocatedBytes,
        allocationMethod: item.allocationMethod,
        createdAt: item.createdAt,
      );
    }
  }

  @override
  Future<void> replaceAllocations(
    String usageRecordId,
    List<UsageAllocation> rows,
  ) async {
    final record = records[usageRecordId];
    if (record == null) {
      throw const AppException(
        AppException.notFound,
        'Catatan pemakaian tidak ditemukan.',
      );
    }
    await _validateAndSaveAllocations(record, usageRecordId, rows);
  }

  @override
  Future<List<UsageAllocation>> getAllocations(String usageRecordId) async {
    return allocations.values
        .where((allocation) => allocation.usageRecordId == usageRecordId)
        .toList();
  }

  @override
  Future<List<UsageAllocation>> getAllocationsByPackage(
    String packageId,
  ) async {
    return allocations.values
        .where((allocation) => allocation.packageId == packageId)
        .toList();
  }
}

class InMemoryDataLimitRepository implements DataLimitRepository {
  InMemoryDataLimitRepository(this.packages) {
    packages.addDeleteListener((id) => items.remove(id));
  }

  final InMemoryPackageRepository packages;
  final Map<String, DataLimitSetting> items = {};

  @override
  Future<DataLimitSetting?> getByPackage(String packageId) async {
    return items[packageId];
  }

  @override
  Future<void> upsert(DataLimitSetting setting) async {
    if (await packages.getById(setting.packageId) == null) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    if ((setting.dailyLimitBytes != null && setting.dailyLimitBytes! <= 0) ||
        setting.warnAtPercent < 1 ||
        setting.warnAtPercent > 100 ||
        setting.limitAtPercent < 1 ||
        setting.limitAtPercent > 100 ||
        setting.warnAtPercent > setting.limitAtPercent) {
      throw const AppException(
        AppException.validation,
        'Pengaturan batas tidak valid.',
      );
    }

    items[setting.packageId] = setting;
  }

  @override
  Future<void> delete(String packageId) async {
    items.remove(packageId);
  }
}

class InMemoryAlertRepository implements AlertRepository {
  InMemoryAlertRepository(this.packages) {
    packages.addDeleteListener(
      (id) => logs.removeWhere((_, alert) => alert.packageId == id),
    );
  }

  final InMemoryPackageRepository packages;
  final Map<String, AlertLog> logs = {};

  int _nextId = 1;

  @override
  Future<String> add(AlertLog alert) async {
    final existing = logs.values
        .where((item) => item.dedupeKey == alert.dedupeKey)
        .firstOrNull;

    if (existing != null) {
      return existing.id!;
    }

    final id = alert.id ?? _memoryId('alert', _nextId++);

    logs[id] = AlertLog(
      id: id,
      packageId: alert.packageId,
      quotaCategoryId: alert.quotaCategoryId,
      alertType: alert.alertType,
      message: alert.message,
      observedBytes: alert.observedBytes,
      thresholdBytes: alert.thresholdBytes,
      dedupeKey: alert.dedupeKey,
      triggeredAt: alert.triggeredAt,
      isRead: alert.isRead,
    );

    return id;
  }

  @override
  Future<bool> existsByDedupeKey(String dedupeKey) async {
    return logs.values.any((alert) => alert.dedupeKey == dedupeKey);
  }

  @override
  Future<List<AlertLog>> getByPackage(String packageId) async {
    final result = logs.values
        .where((alert) => alert.packageId == packageId)
        .toList();

    result.sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    return result;
  }

  @override
  Future<void> markRead(String alertId) async {
    final alert = logs[alertId];

    if (alert == null) {
      throw const AppException(
        AppException.notFound,
        'Notifikasi tidak ditemukan.',
      );
    }

    logs[alertId] = AlertLog(
      id: alert.id,
      packageId: alert.packageId,
      quotaCategoryId: alert.quotaCategoryId,
      alertType: alert.alertType,
      message: alert.message,
      observedBytes: alert.observedBytes,
      thresholdBytes: alert.thresholdBytes,
      dedupeKey: alert.dedupeKey,
      triggeredAt: alert.triggeredAt,
      isRead: true,
    );
  }

  @override
  Future<void> markAllRead(String packageId) async {
    for (final entry in logs.entries.toList()) {
      final alert = entry.value;

      if (alert.packageId == packageId && !alert.isRead) {
        logs[entry.key] = AlertLog(
          id: alert.id,
          packageId: alert.packageId,
          quotaCategoryId: alert.quotaCategoryId,
          alertType: alert.alertType,
          message: alert.message,
          observedBytes: alert.observedBytes,
          thresholdBytes: alert.thresholdBytes,
          dedupeKey: alert.dedupeKey,
          triggeredAt: alert.triggeredAt,
          isRead: true,
        );
      }
    }
  }
}

class InMemorySettingsRepository implements SettingsRepository {
  final Map<String, UserSetting> items = {};

  @override
  Future<UserSetting?> getByUserId(String userId) async {
    return items[userId];
  }

  @override
  Future<void> upsert(UserSetting setting) async {
    if (setting.userId.trim().isEmpty) {
      throw const AppException(AppException.validation, 'User ID wajib diisi.');
    }

    items[setting.userId] = setting;
  }

  @override
  Future<void> delete(String userId) async {
    items.remove(userId);
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
