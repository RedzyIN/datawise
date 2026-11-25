// Ekspor seluruh data lokal milik satu akun ke berkas JSON.
//
// Service hanya membaca lewat Repository, menyusun struktur JSON, lalu
// menyerahkan berkas ke mekanisme berbagi Android. UI tidak menyentuh berkas
// maupun Repository secara langsung.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';

/// Versi struktur berkas ekspor. Naikkan bila bentuk JSON berubah.
const int dataExportFormatVersion = 1;

/// Callback berbagi berkas; dapat diganti pada pengujian.
typedef ShareExportFile = Future<void> Function(File file);

/// Hasil satu proses ekspor.
class DataExportResult {
  const DataExportResult({
    required this.file,
    required this.packageCount,
    required this.usageRecordCount,
    required this.totalRows,
  });

  final File file;
  final int packageCount;
  final int usageRecordCount;
  final int totalRows;

  bool get isEmpty => totalRows == 0;
}

/// Menyusun dan membagikan backup data pengguna yang sedang login.
///
/// Cakupan tabel mengikuti seluruh data lokal per akun:
/// `data_packages`, `quota_categories`, `usage_records`, `usage_allocations`,
/// `classification_rules`, `data_limit_settings`, `user_settings`, dan
/// `alert_logs`. Tabel `users` tidak diekspor karena hanya berisi profil lokal
/// (nama/email) yang tidak diperlukan untuk memulihkan data; UID sudah menjadi
/// akar relasi pada berkas.
class DataExportService {
  DataExportService(
    this._packageRepository,
    this._quotaCategoryRepository,
    this._classificationRuleRepository,
    this._usageRepository,
    this._dataLimitRepository,
    this._alertRepository,
    this._settingsRepository, {
    Future<Directory> Function()? directoryProvider,
    ShareExportFile? shareFile,
  }) : _directoryProvider = directoryProvider ?? getTemporaryDirectory,
       _shareFile = shareFile ?? _shareWithAndroid;

  final PackageRepository _packageRepository;
  final QuotaCategoryRepository _quotaCategoryRepository;
  final ClassificationRuleRepository _classificationRuleRepository;
  final UsageRepository _usageRepository;
  final DataLimitRepository _dataLimitRepository;
  final AlertRepository _alertRepository;
  final SettingsRepository _settingsRepository;

  final Future<Directory> Function() _directoryProvider;
  final ShareExportFile _shareFile;

  /// Membuat struktur JSON ekspor untuk [userId].
  ///
  /// Seluruh data diambil melalui paket milik pengguna, sehingga data akun lain
  /// tidak pernah ikut terbawa. Tidak ada kredensial (password, token Firebase)
  /// yang dibaca atau ditulis: keduanya tidak pernah disimpan di SQLite.
  Future<Map<String, Object?>> buildExportData(
    String userId, {
    DateTime? now,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) {
      throw const AppException(
        AppException.validation,
        'UID pengguna wajib tersedia untuk ekspor.',
      );
    }

    final packages = await _packageRepository.getAll(uid);

    final categories = <Map<String, Object?>>[];
    final usageRecords = <Map<String, Object?>>[];
    final allocations = <Map<String, Object?>>[];
    final rules = <Map<String, Object?>>[];
    final limits = <Map<String, Object?>>[];
    final alerts = <Map<String, Object?>>[];

    for (final package in packages) {
      final packageId = package.id;
      if (packageId == null) continue;

      categories.addAll(
        (await _quotaCategoryRepository.getByPackage(packageId))
            .map((category) => category.toMap()),
      );

      usageRecords.addAll(
        (await _usageRepository.getRecords(packageId))
            .map((record) => record.toMap()),
      );

      allocations.addAll(
        (await _usageRepository.getAllocationsByPackage(packageId))
            .map((allocation) => allocation.toMap()),
      );

      rules.addAll(
        (await _classificationRuleRepository.getByPackage(packageId))
            .map((rule) => rule.toMap()),
      );

      final limit = await _dataLimitRepository.getByPackage(packageId);
      if (limit != null) {
        limits.add(limit.toMap());
      }

      alerts.addAll(
        (await _alertRepository.getByPackage(packageId))
            .map((alert) => alert.toMap()),
      );
    }

    // Hanya preferensi akun ini; berisi mode tema, palet, preferensi
    // notifikasi, dan zona waktu. Tidak ada kredensial di tabel ini.
    final setting = await _settingsRepository.getByUserId(uid);
    final userSettings = setting == null
        ? const <Map<String, Object?>>[]
        : <Map<String, Object?>>[setting.toMap()];

    final summary = <String, int>{
      'packages': packages.length,
      'quota_categories': categories.length,
      'usage_records': usageRecords.length,
      'usage_allocations': allocations.length,
      'classification_rules': rules.length,
      'data_limit_settings': limits.length,
      'user_settings': userSettings.length,
      'alert_logs': alerts.length,
    };

    return <String, Object?>{
      'app_name': 'DATAWISE',
      'format_version': dataExportFormatVersion,
      'app_version': AppConstants.appVersion,
      'exported_at': timeToIso(now ?? DateTime.now()),
      'user_id': uid,
      'summary': summary,
      'data': <String, Object?>{
        'packages': packages.map((package) => package.toMap()).toList(),
        'quota_categories': categories,
        'usage_records': usageRecords,
        'usage_allocations': allocations,
        'classification_rules': rules,
        'data_limit_settings': limits,
        'user_settings': userSettings,
        'alert_logs': alerts,
      },
    };
  }

  /// Membuat berkas JSON lalu membagikannya.
  ///
  /// Kondisi data kosong tetap menghasilkan berkas valid (array kosong) agar
  /// pengguna mendapat file yang dapat dibuka, bukan kegagalan.
  Future<DataExportResult> exportAndShare(
    String userId, {
    DateTime? now,
  }) async {
    final exportedAt = now ?? DateTime.now();
    final data = await buildExportData(userId, now: exportedAt);

    final directory = await _directoryProvider();
    final file = File('${directory.path}/${_fileName(exportedAt)}');

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );

    await _shareFile(file);

    final summary = Map<String, int>.from(data['summary'] as Map);

    return DataExportResult(
      file: file,
      packageCount: summary['packages'] ?? 0,
      usageRecordCount: summary['usage_records'] ?? 0,
      totalRows: summary.values.fold(0, (total, count) => total + count),
    );
  }

  static String _fileName(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');

    return 'datawise_backup_'
        '${time.year}${two(time.month)}${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}.json';
  }

  static Future<void> _shareWithAndroid(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Backup Data DATAWISE',
        text: 'Berkas ekspor data aplikasi DATAWISE.',
      ),
    );
  }
}
