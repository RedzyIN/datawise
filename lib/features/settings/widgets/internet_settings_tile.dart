// PEMILIK: Anggota C. Slot 4 'Pengaturan internet' di halaman Pengaturan.
// Hanya membuka halaman pengaturan Android; aplikasi tidak mengubah
// pengaturan jaringan secara diam-diam.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../usage_monitor/usage_provider.dart';

class InternetSettingsTile extends StatelessWidget {
  const InternetSettingsTile({super.key});

  Future<void> _open(BuildContext context) async {
    final provider = context.read<UsageProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final opened = await provider.openInternetSettings();
    if (opened) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          provider.errorMessage ??
              'Pengaturan jaringan Android tidak dapat dibuka.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Jaringan', style: theme.textTheme.labelLarge),
        ),
        ListTile(
          leading: const Icon(Icons.wifi_tethering),
          title: const Text('Pengaturan internet'),
          subtitle: const Text(
            'Membuka halaman pengaturan jaringan Android. '
            'DATAWISE tidak mengubah pengaturan secara otomatis.',
          ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _open(context),
        ),
      ],
    );
  }
}
