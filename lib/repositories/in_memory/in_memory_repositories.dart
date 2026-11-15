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
      email: user.email?.trim().isEmpty == true
          ? null
          : user.email?.trim(),
    );
  }

  @override
  Future<AppUser?> getById(String uid) async => items[uid];
}

class InMemoryPackageRepository implements PackageRepository {
  final Map<String, DataPackage> _items = {};
  final List<void Function(String)> _deleteListeners = [];
  final List<void Function(DataPackage)> _addListeners = [];
  final List<void Function(DataPackage, DataPackage)> _updateListeners = [];

  int _nextId = 1;

  void addDeleteListener(void Function(String) listener) {
    _deleteListeners.add(listener);
  }

  void addAddListener(void Function(DataPackage) listener) {
    _addListeners.add(listener);
  }

  void addUpdateListener(void Function(DataPackage, DataPackage) listener) {
    _updateListeners.add(listener);
  }

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
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final endDate = DateTime(
      package.endDate.year,
      package.endDate.month,
      package.endDate.day,
    );

    if (package.userId.trim().isEmpty ||
        package.packageName.trim().isEmpty ||
        package.advertisedTotalQuotaBytes <= 0 ||
        package.endDate.isBefore(package.startDate) ||
        (package.status == PackageStatus.active &&
            endDate.isBefore(todayDate))) {
      throw const AppException(
        AppException.validation,
        'Data paket tidak valid atau masa aktif paket sudah berakhir.',
      );
    }
  }

  @override
  Future<String> add(DataPackage package) async {
    _validate(package);

    final id = package.id ?? _memoryId('package', _nextId++);

    final saved = package.copyWith(
      id: id,
      packageName: package.packageName.trim(),
      operatorName: package.operatorName?.trim().isEmpty == true
          ? null
          : package.operatorName?.trim(),
    );

    if (saved.status == PackageStatus.active) {
      _deactivate(saved.userId, id);
    }

    _items[id] = saved;

    for (final listener in _addListeners) {
      listener(saved);
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
    );

    for (final listener in _updateListeners) {
      listener(oldPackage, storedPackage);
    }

    if (storedPackage.status == PackageStatus.active) {
      _deactivate(storedPackage.userId, id);
    }

    _items[id] = storedPackage;
  }

  @override
  Future<void> delete(String packageId) async {
    if (_items.remove(packageId) == null) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    for (final listener in _deleteListeners) {
      listener(packageId);
    }
  }

  @override
  Future<DataPackage?> getById(String packageId) async {
    return _items[packageId];
  }

  @override
  Future<DataPackage?> getActive(String userId) async {
    return _items.values
        .where(
          (package) =>
              package.userId == userId &&
              package.status == PackageStatus.active,
        )
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

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final endDate = DateTime(
      package.endDate.year,
      package.endDate.month,
      package.endDate.day,
    );

    if (package.status == PackageStatus.expired ||
        package.status == PackageStatus.archived ||
        endDate.isBefore(todayDate)) {
      throw const AppException(
        AppException.validation,
        'Paket yang sudah kedaluwarsa atau diarsipkan tidak dapat diaktifkan.',
      );
    }

    for (final entry in _items.entries.toList()) {
      if (entry.value.userId == userId) {
        _items[entry.key] = entry.value.copyWith(
          status: entry.key == packageId
              ? PackageStatus.active
              : PackageStatus.inactive,
        );
      }
    }
  }
}

class InMemoryQuotaCategoryRepository implements QuotaCategoryRepository {
  InMemoryQuotaCategoryRepository(this.packages) {
    packages.addAddListener(_createMainCategory);
    packages.addUpdateListener(_handlePackageUpdate);
    packages.addDeleteListener(_handlePackageDelete);
  }

  final InMemoryPackageRepository packages;
  final Map<String, QuotaCategory> items = {};
  final List<void Function(String)> _deleteListeners = [];

  int _nextId = 1;

  void addDeleteListener(void Function(String) listener) {
    _deleteListeners.add(listener);
  }

  void _createMainCategory(DataPackage package) {
    final id = _memoryId('category', _nextId++);

    items[id] = QuotaCategory(
      id: id,
      packageId: package.id!,
      categoryName: 'Kuota Utama',
      categoryType: QuotaCategoryType.main,
      capacityBytes: package.advertisedTotalQuotaBytes,
      validFrom: package.startDate,
      validUntil: package.endDate,
      isEnabled: true,
      createdAt: package.createdAt,
    );
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
    if (category.categoryName.trim().isEmpty ||
        category.capacityBytes <= 0 ||
        category.categoryType == QuotaCategoryType.main) {
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

    if (category.categoryName.trim().isEmpty || category.capacityBytes <= 0) {
      throw const AppException(
        AppException.validation,
        'Data kategori tidak valid.',
      );
    }

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
            (rule.endMinute! < 0 || rule.endMinute! > 1439)) ||
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
      final priorityComparison = a.priority.compareTo(b.priority);
      return priorityComparison != 0
          ? priorityComparison
          : (a.id ?? '').compareTo(b.id ?? '');
    });

    return result;
  }
}

class InMemoryUsageRepository implements UsageRepository {
  InMemoryUsageRepository(this.packages, [this.categories]) {
    packages.addDeleteListener(_handlePackageDelete);
    categories?.addDeleteListener(_handleCategoryDelete);
  }

  final InMemoryPackageRepository packages;
  final InMemoryQuotaCategoryRepository? categories;

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

  @override
  Future<String> upsertRecord(UsageRecord record) async {
    if (record.rxBytes < 0 ||
        record.txBytes < 0 ||
        !record.periodEndAt.isAfter(record.periodStartAt)) {
      throw const AppException(
        AppException.validation,
        'Data pemakaian tidak valid.',
      );
    }

    if (await packages.getById(record.packageId) == null) {
      throw const AppException(AppException.notFound, 'Paket tidak ditemukan.');
    }

    final matchingSourceKey = record.sourceKey == null
        ? null
        : records.values
              .where((item) => item.sourceKey == record.sourceKey)
              .firstOrNull;

    if (matchingSourceKey != null) {
      if (matchingSourceKey.packageId != record.packageId) {
        throw const AppException(
          AppException.validation,
          'Source key sudah digunakan oleh paket lain.',
        );
      }

      if (record.id != null && record.id != matchingSourceKey.id) {
        throw const AppException(
          AppException.validation,
          'Source key sudah digunakan oleh catatan lain.',
        );
      }
    }

    final existingId = record.id ?? matchingSourceKey?.id;
    final id = existingId ?? _memoryId('usage', _nextRecordId++);

    records[id] = record.copyWith(id: id);

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

    if (record.recordScope != UsageRecordScope.appUsage ||
        record.networkType == NetworkType.wifi) {
      throw const AppException(
        AppException.validation,
        'Catatan pemakaian ini tidak dapat memiliki alokasi kategori.',
      );
    }

    final total = rows.fold<int>(
      0,
      (sum, allocation) => sum + allocation.allocatedBytes,
    );

    if (rows.any((allocation) => allocation.allocatedBytes < 0) ||
        total > record.totalBytes) {
      throw const AppException(
        AppException.validation,
        'Total alokasi tidak valid atau melebihi pemakaian.',
      );
    }

    for (final allocation in rows) {
      if (allocation.packageId != record.packageId ||
          allocation.usageRecordId != usageRecordId) {
        throw const AppException(
          AppException.validation,
          'Alokasi tidak sesuai dengan catatan pemakaian.',
        );
      }

      if (allocation.quotaCategoryId != null && categories != null) {
        final category = await categories!.getById(allocation.quotaCategoryId!);

        if (category == null || category.packageId != record.packageId) {
          throw const AppException(
            AppException.validation,
            'Kategori alokasi tidak sesuai dengan paket.',
          );
        }
      }
    }

    allocations.removeWhere(
      (_, allocation) => allocation.usageRecordId == usageRecordId,
    );

    for (final allocation in rows) {
      final id = allocation.id ?? _memoryId('allocation', _nextAllocationId++);

      allocations[id] = UsageAllocation(
        id: id,
        packageId: allocation.packageId,
        usageRecordId: allocation.usageRecordId,
        quotaCategoryId: allocation.quotaCategoryId,
        classificationRuleId: allocation.classificationRuleId,
        allocatedBytes: allocation.allocatedBytes,
        allocationMethod: allocation.allocationMethod,
        createdAt: allocation.createdAt,
      );
    }
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
