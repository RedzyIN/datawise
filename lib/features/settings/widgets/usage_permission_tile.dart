// PEMILIK: Anggota C (tampilan dirapikan D).
// TODO(C): status izin, tombol 'Berikan izin', cek ulang saat resumed (WidgetsBindingObserver).
import 'package:flutter/material.dart';

class UsagePermissionTile extends StatelessWidget {
  const UsagePermissionTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      title: Text('Izin akses penggunaan'),
      subtitle: Text('TODO(C)'),
    );
  }
}
