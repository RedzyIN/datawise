// PEMILIK: Anggota A (kerangka). C dan D menambah isi lewat PR masing-masing.
// Susunan beku: 1 Akun (A) | 2 Izin data (C) | 3 Notifikasi (D) | 4 Pengaturan internet (C) | 5 Versi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../auth/auth_provider.dart';
import 'widgets/usage_permission_tile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        // 1. Akun
        _AccountSection(),

        // SLOT-C: izin penggunaan data
        UsagePermissionTile(),

        // SLOT-D: notifikasi (tile milik D)

        // SLOT-C: pengaturan internet Android

        // 5. Versi aplikasi
        ListTile(
          title: Text('Versi aplikasi'),
          subtitle: Text(AppConstants.appVersion),
        ),
      ],
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Jika berhasil, AuthGate otomatis kembali ke halaman login.
    await auth.logout();

    final error = auth.errorMessage;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      auth.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Akun', style: Theme.of(context).textTheme.labelLarge),
        ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(auth.currentUser?.email ?? '-'),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Keluar'),
          enabled: !auth.isLoading,
          onTap: () => _confirmLogout(context),
        ),
      ],
    );
  }
}
