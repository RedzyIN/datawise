import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:datawise/models/models.dart';
import 'package:datawise/repositories/repositories.dart';
import 'package:datawise/services/data_export_service.dart';

DataPackage _package({
  required String userId,
  required String name,
  PackageStatus status = PackageStatus.active,
}) {
  return DataPackage(
    userId: userId,
    packageName: name,
    operatorName: 'Telkomsel',
    advertisedTotalQuotaBytes: 10000000000,
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 12, 1),
    status: status,
    createdAt: DateTime(2026, 11, 1, 7),
    updatedAt: DateTime(2026, 11, 1, 7),
  );
}

UsageRecord _deviceUsage(String packageId) {
  return UsageRecord(
    packageId: packageId,
    recordScope: UsageRecordScope.deviceTotal,
    networkType: NetworkType.mobile,
    periodStartAt: DateTime(2026, 11, 12),
    periodEndAt: DateTime(2026, 11, 13),
    rxBytes: 60,
    txBytes: 40,
    source: UsageSource.android,
    sourceKey: 'device_$packageId',
    recordedAt: DateTime(2026, 11, 13),
  );
}

UserSetting _setting(String userId) {
  return UserSetting(
    userId: userId,
    themeMode: 'DARK',
    paletteKey: 'TEAL',
    notificationsEnabled: false,
    timezoneId: 'Asia/Jakarta',
    updatedAt: DateTime(2026, 11, 25, 8),
  );
}

class _ThrowingPackageRepository implements PackageRepository {
  @override
  Future<List<DataPackage>> getAll(String userId) async {
    throw StateError('database tidak dapat dibaca');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late InMemoryPackageRepository packages;
  late InMemoryQuotaCategoryRepository categories;
  late InMemoryClassificationRuleRepository rules;
  late InMemoryUsageRepository usage;
  late InMemoryDataLimitRepository limits;
  late InMemoryAlertRepository alerts;
  late InMemorySettingsRepository settings;
  late DataExportService service;
  File? sharedFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('datawise_export_test');
    packages = InMemoryPackageRepository();
    categories = InMemoryQuotaCategoryRepository(packages);
    rules = InMemoryClassificationRuleRepository(packages, categories);
    usage = InMemoryUsageRepository(packages, categories, rules);
    limits = InMemoryDataLimitRepository(packages);
    alerts = InMemoryAlertRepository(packages);
    settings = InMemorySettingsRepository();
    sharedFile = null;

    service = DataExportService(
      packages,
      categories,
      rules,
      usage,
      limits,
      alerts,
      settings,
      directoryProvider: () async => tempDir,
      shareFile: (file) async => sharedFile = file,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedUserA() async {
    final packageId = await packages.add(
      _package(userId: 'user-a', name: 'Paket A'),
    );

    await usage.upsertRecord(_deviceUsage(packageId));

    final category = (await categories.getByPackage(packageId)).first;
    await rules.add(
      ClassificationRule(
        quotaCategoryId: category.id!,
        ruleName: 'Aturan Malam',
        priority: 1,
        isEnabled: true,
        createdAt: DateTime(2026, 11, 1),
      ),
    );

    await limits.upsert(
      DataLimitSetting(
        packageId: packageId,
        dailyLimitBytes: 500000000,
        isEnabled: true,
        updatedAt: DateTime(2026, 11, 2),
      ),
    );

    await alerts.add(
      AlertLog(
        packageId: packageId,
        alertType: 'daily80',
        message: 'Pemakaian harian mencapai 80%.',
        dedupeKey: 'user-a:package:$packageId:daily80:2026-11-12',
        triggeredAt: DateTime(2026, 11, 12, 18),
        isRead: false,
      ),
    );

    await settings.upsert(_setting('user-a'));
  }

  test('membuat berkas JSON valid yang dapat dibaca kembali', () async {
    await seedUserA();

    final result = await service.exportAndShare('user-a');

    expect(await result.file.exists(), isTrue);
    expect(sharedFile?.path, result.file.path);
    expect(result.packageCount, 1);
    expect(result.usageRecordCount, 1);

    final raw = await result.file.readAsString();
    final decoded = jsonDecode(raw);

    expect(decoded, isA<Map<String, dynamic>>());

    final json = decoded as Map<String, dynamic>;

    expect(json['app_name'], 'DATAWISE');
    expect(json['format_version'], dataExportFormatVersion);
    expect(json['user_id'], 'user-a');
    expect(json['exported_at'], isA<String>());
    expect(json['summary'], isA<Map<String, dynamic>>());
    expect(json['data'], isA<Map<String, dynamic>>());
  });

  test('seluruh tabel milik pengguna ikut diekspor', () async {
    await seedUserA();

    final data = await service.buildExportData('user-a');
    final tables = data['data'] as Map<String, Object?>;
    final summary = data['summary'] as Map<String, int>;

    expect((tables['packages'] as List).length, 1);
    expect((tables['quota_categories'] as List).length, 1);
    expect((tables['usage_records'] as List).length, 1);
    expect((tables['classification_rules'] as List).length, 1);
    expect((tables['data_limit_settings'] as List).length, 1);
    expect((tables['alert_logs'] as List).length, 1);
    expect((tables['user_settings'] as List).length, 1);
    expect(tables['usage_allocations'], isA<List>());

    expect(summary['packages'], 1);
    expect(summary['usage_records'], 1);
    expect(summary['alert_logs'], 1);
    expect(summary['user_settings'], 1);

    final package = (tables['packages'] as List).first as Map;
    expect(package['package_name'], 'Paket A');
    expect(package['user_id'], 'user-a');
  });

  test('data pengguna lain tidak ikut diekspor', () async {
    await seedUserA();
    await packages.add(
      _package(
        userId: 'user-b',
        name: 'Paket Rahasia B',
        status: PackageStatus.inactive,
      ),
    );

    final data = await service.buildExportData('user-a');
    final json = jsonEncode(data);

    expect(json, isNot(contains('Paket Rahasia B')));
    expect(json, isNot(contains('user-b')));
  });

  test('tidak mengekspor password maupun token autentikasi', () async {
    await seedUserA();

    final result = await service.exportAndShare('user-a');
    final raw = (await result.file.readAsString()).toLowerCase();

    expect(raw, isNot(contains('password')));
    expect(raw, isNot(contains('token')));
    expect(raw, isNot(contains('refresh_token')));
    expect(raw, isNot(contains('credential')));
    expect(raw, isNot(contains('@')));
  });

  test('data kosong tetap menghasilkan berkas JSON yang valid', () async {
    final result = await service.exportAndShare('user-tanpa-data');

    expect(result.isEmpty, isTrue);
    expect(await result.file.exists(), isTrue);

    final json =
        jsonDecode(await result.file.readAsString()) as Map<String, dynamic>;
    final tables = json['data'] as Map<String, dynamic>;

    expect(tables['packages'], isEmpty);
    expect(tables['usage_records'], isEmpty);
    expect(tables['user_settings'], isEmpty);
  });

  test('UID kosong ditolak', () async {
    expect(() => service.buildExportData('   '), throwsA(isA<AppException>()));
  });

  test('kegagalan membaca data diteruskan sebagai error', () async {
    final failing = DataExportService(
      _ThrowingPackageRepository(),
      categories,
      rules,
      usage,
      limits,
      alerts,
      settings,
      directoryProvider: () async => tempDir,
      shareFile: (file) async => sharedFile = file,
    );

    await expectLater(
      failing.exportAndShare('user-a'),
      throwsA(isA<StateError>()),
    );

    expect(sharedFile, isNull);
  });
}
