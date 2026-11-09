# Laporan PoC Pembacaan Data Seluler (Minggu 1)

Penulis: Faatih

## Hasil: BERHASIL

## Perangkat uji
- HP: [Redmi Note 13 Pro 5G]
- Android: [16.0]

## Hasil uji
| Skenario | Hasil |
|---|---|
| Izin belum aktif | status permission_denied, tidak crash |
| Izin aktif | status ok, angka muncul |
| Izin dicabut saat aplikasi berjalan | kembali permission_denied, tidak crash |
| Hanya Wi-Fi | angka tidak bertambah, tidak ada error |
| Data seluler dipakai | angka naik dari [107.92] MB ke [119.91] MB |

## Perbandingan dengan Pengaturan HP
- Selisih di aplikasi: [12] MB
- Selisih di Pengaturan HP: [11.8] MB
- Perbedaan: [0.2] MB
- Catatan: [Selisih diambang aman, yang menyatakan bahwa datawise hampir memiliki akurat sama persis dengan device android yang diuji]

## Kesimpulan
Pembacaan data seluler berjalan di HP asli. Jalur utama memakai pembacaan
otomatis, dan input manual tetap tersedia sebagai cadangan.
Kode PoC sama dengan `UsageChannel.kt` yang sudah ada di repo.