# ERD (Kontrak beku #2) — datawise.db v1

```
data_packages (1) ──< (banyak) usage_records   ON DELETE CASCADE
data_packages (1) ──< (banyak) alert_logs      ON DELETE CASCADE
app_settings  (berdiri sendiri)
```

SQL lengkap ada di `lib/core/db_helper.dart`. Aturan pakai:
- Pemakaian efektif satu hari = nilai `manual` jika ada, jika tidak `auto`.
- Total terpakai paket = `initial_used_bytes` + jumlah pemakaian efektif semua hari.
- Satuan: byte (1 GB = 1.000.000.000). Tanggal: `YYYY-MM-DD`. Waktu: ms UTC.
