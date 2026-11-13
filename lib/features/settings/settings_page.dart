// PEMILIK: Anggota A (kerangka). C dan D menambah isi lewat PR masing-masing.
// Susunan beku: 1 Akun (A) | 2 Izin data (C) | 3 Notifikasi (D) | 4 Pengaturan internet (C) | 5 Versi.
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'widgets/usage_permission_tile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        // 1. Akun
        ListTile(title: Text('Akun'), subtitle: Text('TODO(A): email + tombol Keluar')),

        // SLOT-C: izin penggunaan data
        UsagePermissionTile(),

        // SLOT-D: notifikasi (tile milik D)

        // SLOT-C: pengaturan internet Android

        // 5. Versi aplikasi
        ListTile(title: Text('Versi aplikasi'), subtitle: Text(AppConstants.appVersion)),
      ],
    );
  }
}
