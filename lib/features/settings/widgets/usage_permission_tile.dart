// Status izin Usage Access Android yang sebenarnya, beserta tombol izin.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_provider.dart';

class UsagePermissionTile extends StatefulWidget {
  const UsagePermissionTile({super.key});

  @override
  State<UsagePermissionTile> createState() => _UsagePermissionTileState();
}

class _UsagePermissionTileState extends State<UsagePermissionTile>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Izin Android tidak terikat akun, jadi statusnya dibaca saat tile tampil.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SettingsProvider>().refreshUsagePermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pengguna bisa mengubah izin dari halaman Pengaturan Android, jadi status
    // diperiksa ulang setiap kali aplikasi kembali aktif.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<SettingsProvider>().refreshUsagePermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final granted = settings.usagePermissionGranted;
    final checking = settings.isCheckingPermission;

    return ListTile(
      leading: Icon(
        granted ? Icons.verified_user_outlined : Icons.privacy_tip_outlined,
      ),
      title: const Text('Izin akses penggunaan'),
      subtitle: Text(
        granted
            ? 'Diizinkan. DATAWISE dapat membaca statistik pemakaian perangkat.'
            : 'Belum diizinkan. Statistik pemakaian tidak dapat dibaca.',
      ),
      trailing: granted
          ? (checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle, semanticLabel: 'Diizinkan'))
          : TextButton(
              onPressed: checking ? null : settings.requestUsagePermission,
              child: const Text('Berikan izin'),
            ),
    );
  }
}
