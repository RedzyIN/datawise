import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme_provider.dart';
import '../alerts/alert_history_page.dart';
import '../alerts/alert_simulation_page.dart';
import '../auth/auth_provider.dart';
import 'color_palette_page.dart';
import 'settings_provider.dart';
import 'widgets/usage_permission_tile.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _lastUid;
  bool _preferencesSynced = false;

  /// Memuat preferensi sesuai akun aktif. Pergantian akun me-reset state
  /// sehingga preferensi satu pengguna tidak terbawa ke pengguna lain.
  void _syncPreferences(String? uid) {
    if (_preferencesSynced && uid == _lastUid) return;

    _preferencesSynced = true;
    _lastUid = uid;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SettingsProvider>().loadForUser(uid);
    });
  }

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

    // Logout hanya mengakhiri sesi Firebase. Data SQLite milik akun tetap utuh.
    await auth.logout();

    if (!context.mounted) return;

    if (auth.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(auth.errorMessage!)));
    }
  }

  Future<void> _exportData(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    await settings.exportData();

    if (!context.mounted) return;

    final message = settings.exportMessage ?? settings.errorMessage;
    if (message == null) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final user = auth.currentUser;

    _syncPreferences(user?.uid);

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
            label: Text(auth.isLoading ? 'Memproses...' : 'Keluar dari Akun'),
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
            subtitle: Text('Atur tampilan terang, gelap, dan warna aplikasi'),
          ),
        ),

        // Pengaturan Light dan Dark Mode
        Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            final isDark = themeProvider.themeMode == ThemeMode.dark;

            return SwitchListTile(
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              title: const Text('Dark Mode'),
              subtitle: Text(isDark ? 'Mode gelap aktif' : 'Mode terang aktif'),
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
              title: const Text('Palet Warna'),
              subtitle: Text('Warna saat ini: ${themeProvider.palette.name}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ColorPalettePage()),
                );
              },
            );
          },
        ),

        const Divider(height: 32),

        // 3. Data & Notifikasi
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Data & Notifikasi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        // Data Export & Backup - FUT-08
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Ekspor & Backup Data'),
          subtitle: Text(
            settings.isExporting
                ? 'Menyiapkan berkas backup...'
                : 'Simpan seluruh data lokal akun ini ke berkas JSON',
          ),
          trailing: settings.isExporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.share),
          enabled: user != null && !settings.isExporting,
          onTap: user == null || settings.isExporting
              ? null
              : () => _exportData(context, settings),
        ),

        // SLOT-C: izin penggunaan data
        const UsagePermissionTile(),

        // Preferensi notifikasi aplikasi (berbeda dengan izin Android).
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Notifikasi aplikasi'),
          subtitle: Text(
            '${settings.notificationsEnabled ? 'Aktif' : 'Nonaktif'}. '
            'Preferensi ini hanya mengatur peringatan dari DATAWISE; izin '
            'notifikasi Android tetap diatur di pengaturan sistem.',
          ),
          value: settings.notificationsEnabled,
          onChanged: user == null
              ? null
              : (value) => unawaited(settings.setNotificationsEnabled(value)),
        ),

        // SLOT-D: notifikasi milik Anggota D
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Riwayat Notifikasi'),
          subtitle: const Text(
            'Peringatan target, sisa kuota, dan masa aktif paket',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertHistoryPage()),
            );
          },
        ),

        // Tombol simulasi hanya ada pada build debug.
        if (kDebugMode)
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Simulasi Smart Alert'),
            subtitle: const Text('Debug: picu event alert terkontrol'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlertSimulationPage()),
              );
            },
          ),

        const Divider(height: 32),

        // 4. Informasi aplikasi
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Versi aplikasi'),
          subtitle: Text(AppConstants.appVersion),
        ),
      ],
    );
  }
}
