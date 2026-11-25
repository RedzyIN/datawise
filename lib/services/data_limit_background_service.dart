// Evaluasi Data Limit Warning di luar UI (Android WorkManager).
//
// Alur normal tetap: UI -> Provider -> DataLimitService. Worker ini hanya
// menjalankan jalur yang sama tanpa UI, memakai repository SQLite yang sama
// sehingga AlertLog, deduplikasi, dan Notification Center tetap konsisten.
//
// Batasan Android yang perlu dipahami:
// - WorkManager periodik memiliki interval minimum 15 menit dan dijadwalkan
//   oleh sistem (best-effort, bukan real-time). Doze, hemat baterai, atau
//   pembersih memori vendor dapat menunda/menghentikan tugas.
// - Android tidak menyediakan API pemantauan pemakaian data real-time untuk
//   aplikasi latar belakang, sehingga notifikasi hanya dapat muncul setelah
//   worker dieksekusi, bukan tepat pada detik ambang terlampaui.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../models/models.dart';
import '../repositories/package_repository.dart';
import '../repositories/sqlite/sqlite_repositories.dart';
import 'data_limit_service.dart';
import 'local_notification_service.dart';

/// Nama tugas yang dikirim ke [Workmanager].
const String dataLimitPeriodicTaskName = 'datawiseDataLimitCheck';

/// Nama unik pekerjaan periodik (dipakai untuk mengganti/membatalkan).
const String dataLimitPeriodicUniqueName = 'datawise-data-limit-periodic';

/// Interval minimum yang diizinkan WorkManager.
const Duration dataLimitCheckFrequency = Duration(minutes: 15);

/// Titik masuk isolate background. Harus top-level dan ditandai
/// `vm:entry-point` agar tidak dibuang saat kompilasi AOT.
@pragma('vm:entry-point')
void dataLimitBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != dataLimitPeriodicTaskName) return true;

    WidgetsFlutterBinding.ensureInitialized();

    try {
      await DataLimitBackgroundRunner.run();
    } catch (error) {
      debugPrint('Data limit background task gagal: $error');
    }

    // Selalu `true`: kegagalan sudah ditangani dengan mencoba lagi pada
    // jadwal periodik berikutnya, bukan dengan retry-backoff WorkManager.
    return true;
  });
}

/// Menjalankan evaluasi untuk seluruh paket aktif di perangkat.
class DataLimitBackgroundRunner {
  const DataLimitBackgroundRunner._();

  /// Memakai repository SQLite produksi. Tidak menerima UID dari Firebase
  /// karena isolate background tidak memiliki sesi login; pemilik paket dibaca
  /// dari `data_packages.user_id` lewat [PackageRepository.getActivePackages].
  static Future<void> run() async {
    final dataLimitService = DataLimitService(
      SqliteDataLimitRepository(),
      SqliteUsageRepository(),
      SqliteAlertRepository(),
      SqliteSettingsRepository(),
      FlutterLocalNotificationService(),
    );

    await evaluate(
      packageRepo: SqlitePackageRepository(),
      dataLimitService: dataLimitService,
    );
  }

  /// Logika murni evaluasi, dapat diuji dengan repository in-memory.
  /// Mengembalikan jumlah paket aktif yang dievaluasi.
  ///
  /// Pemakaian yang dievaluasi adalah catatan terakhir di SQLite, bukan angka
  /// langsung dari perangkat: channel pemakaian hanya tersedia di engine UI.
  /// Karena itu worker dapat melewatkan ambang yang baru saja terlampaui, tetapi
  /// tidak pernah mengarang pemakaian yang belum tercatat.
  static Future<int> evaluate({
    required PackageRepository packageRepo,
    required DataLimitService dataLimitService,
    DateTime? now,
  }) async {
    final triggeredAt = now ?? DateTime.now();
    final today = dateOnly(triggeredAt);

    final activePackages = await packageRepo.getActivePackages();
    var evaluated = 0;

    for (final package in activePackages) {
      final packageId = package.id;
      if (packageId == null || packageId.isEmpty) continue;

      final usedBytes = await dataLimitService.usedBytesOn(packageId, today);
      final plannerResult = await dataLimitService.plannerResultFor(
        package,
        now: triggeredAt,
      );

      // Peringatan yang dinonaktifkan (per paket maupun di Pengaturan) dan paket
      // yang kedaluwarsa sudah disaring di dalam evaluateAndNotify, sehingga
      // aturan itu hanya ditulis sekali.
      await dataLimitService.evaluateAndNotify(
        packageId: packageId,
        userId: package.userId,
        usedBytes: usedBytes,
        plannerResult: plannerResult,
        now: triggeredAt,
      );

      evaluated++;
    }

    return evaluated;
  }
}

/// Pendaftaran pekerjaan periodik. Kegagalan pendaftaran tidak boleh
/// menghentikan aplikasi; evaluasi di dalam aplikasi tetap berjalan.
class DataLimitBackgroundScheduler {
  const DataLimitBackgroundScheduler._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid || _initialized) return;

    try {
      await Workmanager().initialize(dataLimitBackgroundDispatcher);
      _initialized = true;
    } catch (error) {
      debugPrint('Workmanager gagal diinisialisasi: $error');
    }
  }

  /// Mendaftarkan pemeriksaan periodik. Aman dipanggil berulang kali:
  /// pekerjaan yang sudah ada dipertahankan (`keep`).
  static Future<void> schedule() async {
    await initialize();

    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await Workmanager().registerPeriodicTask(
        dataLimitPeriodicUniqueName,
        dataLimitPeriodicTaskName,
        frequency: dataLimitCheckFrequency,
        // Constraints bawaan: tidak memerlukan jaringan (notRequired).
        constraints: Constraints(),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (error) {
      debugPrint('Gagal menjadwalkan pemeriksaan batas data: $error');
    }
  }

  /// Menghentikan pemeriksaan latar belakang (mis. pengguna mematikan seluruh
  /// peringatan).
  static Future<void> cancel() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await Workmanager().cancelByUniqueName(dataLimitPeriodicUniqueName);
    } catch (error) {
      debugPrint('Gagal menghentikan pemeriksaan batas data: $error');
    }
  }
}
