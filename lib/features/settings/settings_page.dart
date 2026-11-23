import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme_provider.dart';
import '../auth/auth_provider.dart';
import 'widgets/usage_permission_tile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _confirmLogout(BuildContext context, AuthProvider auth) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Keluar dari akun?'),
          content: const Text(
            'Apakah kamu yakin ingin keluar dari akun DATAWISE?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Keluar'),
            ),
          ],
        );
      },
    );

    if (result != true || !context.mounted) return;

    await auth.logout();

    if (!context.mounted) return;

    if (auth.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(auth.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        final user = auth.currentUser;

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // 1. Profil pengguna
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Profil Pengguna',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),

            ListTile(
              leading: const CircleAvatar(
                radius: 26,
                child: Icon(Icons.person, size: 30),
              ),
              title: Text(
                user?.email ?? 'Tidak ada akun',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: user == null
                  ? const Text('Belum ada pengguna yang login')
                  : SelectableText('UID: ${user.uid}'),
            ),

            // Tombol keluar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: auth.isLoading || user == null
                    ? null
                    : () => _confirmLogout(context, auth),
                icon: auth.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout),
                label: Text(
                  auth.isLoading ? 'Memproses...' : 'Keluar dari Akun',
                ),
              ),
            ),

            const Divider(height: 32),

            // 2. Pengaturan tema
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.palette_outlined),
                title: Text('Tampilan Aplikasi'),
                subtitle: Text('Atur tampilan terang atau gelap'),
              ),
            ),

            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                final isDark = themeProvider.themeMode == ThemeMode.dark;

                return SwitchListTile(
                  secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
                  title: const Text('Dark Mode'),
                  subtitle: Text(
                    isDark ? 'Mode gelap aktif' : 'Mode terang aktif',
                  ),
                  value: isDark,
                  onChanged: (value) {
                    themeProvider.setThemeMode(
                      value ? ThemeMode.dark : ThemeMode.light,
                    );
                  },
                );
              },
            ),

            const Divider(height: 32),

            // SLOT-C: izin penggunaan data
            const UsagePermissionTile(),

            // SLOT-D: notifikasi milik Anggota D

            // SLOT-C: pengaturan internet Android
            const Divider(height: 32),

            // 3. Informasi aplikasi
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Versi aplikasi'),
              subtitle: Text(AppConstants.appVersion),
            ),
          ],
        );
      },
    );
  }
}
