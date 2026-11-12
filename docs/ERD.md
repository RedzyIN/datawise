# ERD DATAWISE v1.0

Kontrak lengkap database, model, dan repository: [KONTRAK_DATA_V1.md](KONTRAK_DATA_V1.md).

## Relasi tabel

```
data_packages
 ├── quota_categories
 │    ├── classification_rules
 │    └── usage_allocations
 ├── usage_records
 │    └── usage_allocations
 ├── data_limit_settings
 └── alert_logs

user_settings (berdasarkan Firebase UID, tidak memakai tabel users lokal)
```

Seluruh relasi lokal memakai INTEGER foreign key dan ON DELETE CASCADE. `user_settings` memakai primary key gabungan `(user_id, key)`.

## Tabel

1. `data_packages`: paket internet milik Firebase UID.
2. `quota_categories`: kategori kuota per paket, termasuk kategori main.
3. `usage_records`: catatan pemakaian harian dari sumber auto atau manual.
4. `classification_rules`: aturan klasifikasi aplikasi dan rentang waktu ke kategori.
5. `usage_allocations`: hasil pembagian pemakaian record ke kategori.
6. `data_limit_settings`: pengaturan peringatan batas paket.
7. `user_settings`: preferensi pengguna.
8. `alert_logs`: riwayat notifikasi agar notifikasi yang sama tidak dikirim berulang.

## Aturan data penting

- Satu pengguna hanya memiliki satu paket aktif.
- Satu paket wajib memiliki tepat satu kategori main.
- Jumlah kuota seluruh kategori harus sama dengan total kuota paket.
- Jika record auto dan manual ada pada tanggal yang sama, record manual menjadi pemakaian efektif. Keduanya tidak dijumlahkan.
- Alokasi kategori dihitung hanya dari record efektif.
- Total alokasi satu record tidak boleh melebihi used_bytes record tersebut.
- Data yang tidak cocok dengan aturan klasifikasi masuk kategori main.
- 1 GB = 1.000.000.000 byte.
- Tanggal disimpan sebagai YYYY-MM-DD. Timestamp disimpan sebagai Unix epoch milliseconds UTC.

SQL final dan tanda tangan model/repository hanya ada di [KONTRAK_DATA_V1.md](KONTRAK_DATA_V1.md). Jangan mengubah skema melalui dokumen ini saja.
