# DATAWISE

Aplikasi Flutter (Android) untuk merencanakan pemakaian kuota internet: target harian/mingguan,
pembacaan pemakaian data seluler, notifikasi, dan riwayat paket.

- Android saja, minSdk 29 · `applicationId` `com.datawise.datawise`
- Firebase Auth (email + password) · SQLite (`sqflite`, `datawise.db` v1) · state: `provider`
- Versi Flutter tim: **`TULIS_HASIL flutter --version DI SINI`**

## Pembagian kerja

| Anggota | Peran | Branch | Folder / file utama |
|---------|-------|--------|---------------------|
| Muh. Resky Putra Ramadhan | Arsitek sistem & database | `develop`, `main` | `core/`, `models/`, `repositories/`, `main.dart`, `pubspec.yaml` |
| Muh Darmawan Alif Syahputra | Authentication | `feature/auth` | `services/auth_service.dart`, `features/auth/`, `features/settings/settings_page.dart` |
| Fitri Ramadani | Fungsi inti (Planner & Paket) | `feature/package-planner` | `services/planner_service.dart`, `features/package/` |
| Faatih Alfaredzy Iansyah Nusi | Android integration | `feature/usage-monitor` | `services/usage_service.dart`, `features/usage_monitor/`, `android/.../kotlin/`, `settings/widgets/` |
| Besse Fitri Ramadani(Nero) | UI/UX & Dashboard | `feature/dashboard` | `features/dashboard/`, `features/history/`, `shared/`, `services/alert_service.dart` |

Aturan pemanggilan: **UI → Provider → Service/Repository → SQLite/Firebase/Android.**
UI tidak memanggil Repository atau MethodChannel langsung.

## Struktur

```
lib/
├── core/            (Resky)  constants, format_utils, routes, app_providers, theme, db_helper, home_shell
├── models/          (Resky)  kontrak beku #3
├── repositories/    (Resky)  interface + in_memory/ (minggu 1) → sqflite (minggu 2)
├── services/        auth(Darmawan) planner(Fitri) usage(Faatih) alert(Nero)
├── features/        auth(Darmawan) package(Fitri) usage_monitor(Faatih) dashboard(Nero) history(Nero) settings(Darmawan,Faatih,Nero)
├── shared/          (Nero)
└── main.dart        (Resky)
test/                satu sub-folder per fitur
docs/                ERD & konflik antar dokumen
```

## Memulai (Faatih)

```bash
# 1. Buat proyek Flutter
flutter create --org com.datawise --project-name datawise --platforms android datawise
cd datawise

# 2. Salin isi kerangka ini ke dalam folder proyek (timpa file yang sama), lalu:
rm test/widget_test.dart          # Windows PowerShell: del test\widget_test.dart

# 3. Package (hanya yang disetujui kontrak)
flutter pub add firebase_core firebase_auth provider sqflite path \
  flutter_local_notifications timezone flutter_timezone fl_chart intl
flutter pub add --dev flutter_lints

# 4. Firebase (Authentication > Email/Password aktif di Console)
dart pub global activate flutterfire_cli
flutterfire configure              # membuat lib/firebase_options.dart + google-services.json

# 5. minSdk 29: android/app/build.gradle(.kts) -> minSdk = 29
# 6. AndroidManifest.xml: tambahkan xmlns:tools pada <manifest> dan:
#    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
#        tools:ignore="ProtectedPermissions" />

flutter pub get && flutter analyze && flutter run
```

## Push ke GitHub (Faatih)

```bash
git init -b main
git add .
git commit -m "feat: kerangka proyek DATAWISE (kontrak beku v1.0)"
git remote add origin https://github.com/RedzyIN/datawise
git push -u origin main
git checkout -b develop && git push -u origin develop
```

Lalu di GitHub: jadikan repo **private**, undang A–D, aktifkan **branch protection** pada `main` dan
`develop` (wajib PR + review, tidak boleh push langsung), dan ganti placeholder di `.github/CODEOWNERS`.

## Memulai (Darmawan, Fitri, Nero, Resky)

```bash
git clone https://github.com/RedzyIN/datawise.git && cd datawise
git checkout develop && git checkout -b feature/<nama-branch-kamu>
flutter pub get && flutter run
```

Sebelum PR: `flutter analyze` dan `flutter test` harus bersih. Commit berawalan `feat:`, `fix:`, `docs:`, `test:`.
Cari `TODO(A)(Darmawan)`, `TODO(B)(Fitri)`, `TODO(C)(Faatih)`, `TODO(D)(Nero)` untuk bagian milikmu.

> **Baca `docs/KONFLIK_ANTAR_DOKUMEN.md`** — ada beberapa perbedaan antar PRD yang perlu diputuskan Arsitek.