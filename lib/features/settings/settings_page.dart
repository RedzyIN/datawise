import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme_provider.dart';
import '../../repositories/package_repository.dart';
import '../../repositories/usage_repository.dart';
import '../../services/data_export_service.dart';
import '../auth/auth_provider.dart';
import 'color_palette_page.dart';
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

  Future<void> _exportData(BuildContext context, String userId) async {
    try {
      final exportService = DataExportService(
        context.read<PackageRepository>(),
        context.read<UsageRepository>(),
      );

      await exportService.exportAndShare(userId);
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal mengekspor data: $e')));
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
                subtitle: Text(
                  'Atur tampilan terang, gelap, dan warna aplikasi',
                ),
              ),
            ),

            // Pengaturan Light dan Dark Mode
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

            // Menu pemilihan palet warna
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return ListTile(
                  leading: const Icon(Icons.color_lens_outlined),
                  title: const Text('Color Palette'),
                  subtitle: Text(
                    'Warna saat ini: ${themeProvider.palette.name}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ColorPalettePage(),
                      ),
                    );
                  },
                );
              },
            ),

            const Divider(height: 32),

            // 3. Data Export & Backup - FUT-08
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Ekspor & Backup Data'),
              subtitle: const Text(
                'Simpan paket dan riwayat pemakaian ke file JSON',
              ),
              trailing: const Icon(Icons.share),
              enabled: user != null,
              onTap: user == null ? null : () => _exportData(context, user.uid),
            ),

            const Divider(height: 32),

            // SLOT-C: izin penggunaan data
            const UsagePermissionTile(),

            // SLOT-D: notifikasi milik Anggota D

            // SLOT-C: pengaturan internet Android
            const Divider(height: 32),

            // 4. Informasi aplikasi
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
