
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../repositories/package_repository.dart';
import '../repositories/usage_repository.dart';

class DataExportService {
  DataExportService(
    this._packageRepository,
    this._usageRepository,
  );

  final PackageRepository _packageRepository;
  final UsageRepository _usageRepository;

  Future<ShareResult> exportAndShare(String userId) async {
    // Mengambil paket milik pengguna yang sedang login.
    final packages = await _packageRepository.getAll(userId);

    // Mengambil riwayat pemakaian setiap paket.
    final List<Map<String, dynamic>> usageRecords = [];

    for (final package in packages) {
      if (package.id == null) continue;

      final records =
          await _usageRepository.getRecords(package.id!);

      usageRecords.addAll(
        records.map((record) => record.toMap()),
      );
    }

    // Menyusun data yang akan diekspor.
    final exportData = {
      'app_name': 'DATAWISE',
      'exported_at': DateTime.now().toIso8601String(),
      'packages': packages.map((package) => package.toMap()).toList(),
      'usage_records': usageRecords,
    };

    final jsonString =
        const JsonEncoder.withIndent('  ').convert(exportData);

    // Membuat file JSON sementara.
    final directory = await getTemporaryDirectory();

    final now = DateTime.now();
    final fileName =
        'datawise_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour}${now.minute}${now.second}.json';

    final file = File('${directory.path}/$fileName');

    await file.writeAsString(jsonString, flush: true);

    // Membagikan file melalui menu berbagi Android.
    return SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: 'application/json',
          ),
        ],
        subject: 'Backup Data DATAWISE',
        text: 'File ekspor data aplikasi DATAWISE.',
      ),
    );
  }
}
