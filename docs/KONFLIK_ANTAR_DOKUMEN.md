# Konflik antar dokumen PRD (harus diputuskan Arsitek sebelum dibagikan)

Aturan: dokumen Arsitek (01) menang. Kerangka kode ini mengikuti dokumen Arsitek,
dan jika Arsitek diam, mengikuti dokumen anggota yang paling spesifik.
**Dokumen Anggota D (Nero) paling banyak berbeda — perbarui sebelum dibagikan.**

| # | Topik | Arsitek / A / B / C | Dokumen D (Nero) | Dipakai di kerangka |
|---|-------|---------------------|------------------|---------------------|
| 1 | 1 GB | 1.000.000.000 byte | 1.073.741.824 (1024³) | 1.000.000.000 |
| 2 | minSdk | 29 (Android 10) | 24 (Android 7.0) | 29 |
| 3 | applicationId | com.datawise.datawise | com.datawise.app | com.datawise.datawise |
| 4 | Hasil planner | `PlannerResult`, `PlannerStatus {normal, notStarted, depleted, expired}` | `PlanResult`, `PlanStatus {…quotaExhausted…}`, field `totalQuotaBytes`, `usedPercent`, `planStatus`, `usageStatus` | PlannerResult (Arsitek) |
| 5 | Return fungsi | Langsung nilai / lempar `AppException` | `Result<T>` (Success/Failure), `AppError` | AppException |
| 6 | Ambang status harian | daily100: 100–100,5%; dailyOver > 100,5% | reached 100–<110%, overTarget ≥ 110% | Arsitek |
| 7 | Nama AlertType | daily80, daily100, dailyOver, quota10, expiring1d | target80, target100, targetOver, quotaLow10, expiring1Day | Arsitek |
| 8 | alert_date quota10 | endDate paket | start_date paket | endDate (Arsitek) |
| 9 | expiring1d | hari ini = endDate − 1 | remainingDays == 1 | Arsitek |
| 10 | Kunci setting notifikasi | `notif_enabled` ('1'/'0') | `notifications_enabled` ("true") + `usage_guide_seen` | notif_enabled |
| 11 | Koreksi manual | `usage_records.source = 'manual'` + `initial_used_bytes` | kolom `adjustment_bytes` (tidak ada di DB) | Arsitek |
| 12 | Fungsi repository | `getRecords`, `getUsedBytesOn`, `getTotalUsedBytes`, `getDailyUsage` | `getActive(uid, today)`, `getRecord`, `getTotalEffectiveBytes`, `getLastRecordDate`, `getLastUpdatedAt`, `wasSent` | Arsitek |
| 13 | Service C | `UsageService` (`refreshToday`, …) | `UsageMonitorService` (`syncUsage`, `saveManualUsage`) | UsageService |
| 14 | `evaluateAndNotify` | `(package, result)` → void | `({package, plan, today})` → `Result<List<AlertType>>` | Arsitek |
| 15 | Route | `/home`, `/package/form`, `/package/detail`, `/usage/manual` | `/dashboard`, `/packages`, `/package-form`, `/history`, `/history-detail`, `/settings` | Arsitek |
| 16 | File helper format | `core/format_utils.dart` (dok. B) | `core/formatters.dart` | format_utils.dart |
| 17 | Konstruktor `AppException` | `const AppException(code, message)` posisi (dok. B) | `AppException(code: …, message: …)` bernama (dok. A) | posisi |
| 18 | Password minimum | 8 karakter + huruf + angka (dok. A) | "Minimal 6 karakter" (desain D) | 8 karakter |
| 19 | Aturan paket | endDate > startDate (min. 2 hari) | sama | sama |
| 20 | Label tab 1 | "Dashboard" | "Beranda" | Beranda (label saja) |
| 21 | Folder tema | `core/theme.dart` (Arsitek) | `lib/shared/app_theme.dart` (D) | keduanya: dasar di core, D menyempurnakan di shared |
| 22 | Akses total terpakai dari UI | UI tidak boleh memanggil repository | B butuh `getTotalUsedBytes` lewat provider | **Belum ada keputusan** — Arsitek perlu menyediakan akses lewat provider |
| 23 | Nama tabel pemakaian di D | — | "pemakaian efektif = baca + koreksi" | efektif = manual jika ada, else auto |
| 24 | Rumus persen hari ini | `terpakaiHariIni / targetHarian` (tanpa ×100, dok. Arsitek/C) | — | ×100, skala 0–100+ (klarifikasi dok. B) |

## Hal yang belum ada di kontrak (perlu keputusan)
- Cara `PackageDetailPage`/`DashboardProvider` mendapat `totalUsedBytes` (butuh provider/akses repository).
- Route `history-detail` (D) belum ada di route beku.
- Tanda tangan konstruktor `UsageProvider` dan `DashboardProvider` belum dibekukan (di kerangka: ditentukan sementara).
- Sumber `userId` untuk `DashboardProvider.refresh` (kerangka: dikirim sebagai argumen dari UI via `AuthProvider`).
