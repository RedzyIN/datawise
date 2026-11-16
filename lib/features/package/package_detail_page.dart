import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_format.dart';
import 'package_provider.dart';

class PackageDetailPage extends StatefulWidget {
  const PackageDetailPage({super.key});

  @override
  State<PackageDetailPage> createState() => _PackageDetailPageState();
}

class _PackageDetailPageState extends State<PackageDetailPage> {
  String? _packageId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_packageId != null) return;

    final argument = ModalRoute.of(context)?.settings.arguments;
    if (argument is String) _packageId = argument;
  }

  String _statusLabel(DataPackage p) {
    if (p.isArchived) return 'Diarsipkan';
    if (p.isExpiredAt()) return 'Kedaluwarsa';
    return p.status == PackageStatus.active ? 'Paket Utama' : 'Paket Tambahan';
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editPackage(DataPackage package) async {
    await Navigator.pushNamed(context, Routes.packageForm, arguments: package);
  }

  Future<void> _setActive(DataPackage package) async {
    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || package.id == null) return;

    final provider = context.read<PackageProvider>();
    provider.clearError();

    final ok = await provider.setActive(userId, package.id!);
    if (!mounted) return;

    _snack(
      ok
          ? 'Paket utama berhasil diubah.'
          : provider.errorMessage ?? 'Gagal mengaktifkan paket.',
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _archivePackage(DataPackage package) async {
    final confirmed = await _confirm(
      title: 'Arsipkan Paket?',
      message:
          'Paket "${package.packageName}" akan dipindahkan ke arsip. '
          'Kategori, catatan penggunaan, aturan, dan riwayat notifikasi '
          'tetap disimpan.',
      confirmLabel: 'Arsipkan',
    );

    if (!confirmed || !mounted) return;

    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || package.id == null) return;

    final provider = context.read<PackageProvider>();
    provider.clearError();

    final success = await provider.archivePackage(package.id!, userId);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
    } else {
      _snack(provider.errorMessage ?? 'Gagal mengarsipkan paket.');
    }
  }

  Future<void> _deletePackage(DataPackage package) async {
    final provider = context.read<PackageProvider>();

    final hasUsage = await provider.hasUsageHistory(package.id!);
    if (!mounted) return;

    // Aturan kontrak data: paket dengan riwayat pemakaian tidak boleh dihapus.
    if (hasUsage) {
      final archive = await _confirm(
        title: 'Paket Tidak Dapat Dihapus',
        message:
            'Paket "${package.packageName}" sudah memiliki riwayat '
            'pemakaian sehingga tidak boleh dihapus. '
            'Anda dapat mengarsipkannya agar tidak muncul di daftar aktif.',
        confirmLabel: 'Arsipkan',
      );
      if (archive && mounted && !package.isArchived) {
        await _archivePackage(package);
      }
      return;
    }

    final confirmed = await _confirm(
      title: 'Hapus Paket?',
      message:
          'Paket "${package.packageName}" akan dihapus permanen. '
          'Tindakan ini tidak dapat dibatalkan.',
      confirmLabel: 'Hapus Permanen',
    );

    if (!confirmed || !mounted) return;

    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || package.id == null) return;

    provider.clearError();
    final success = await provider.deletePackage(package.id!, userId);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
    } else {
      _snack(provider.errorMessage ?? 'Gagal menghapus paket.');
    }
  }

  Widget _buildInfo({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PackageProvider>(
      builder: (context, provider, child) {
        final package = provider.findById(_packageId);

        if (package == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detail Paket')),
            body: Center(
              child: Text(
                provider.isLoading
                    ? 'Memuat data paket...'
                    : 'Paket tidak ditemukan.',
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        final expired = package.isExpiredAt();
        final archived = package.isArchived;
        final isActive = package.status == PackageStatus.active && !expired;
        final canActivate = !isActive && !expired && !archived;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Detail Paket'),
            actions: [
              IconButton(
                tooltip: 'Edit paket',
                onPressed: provider.isLoading
                    ? null
                    : () => _editPackage(package),
                icon: const Icon(Icons.edit),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.packageName,
                        style: theme.textTheme.headlineSmall,
                      ),
                      if ((package.operatorName ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          package.operatorName!,
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          Chip(label: Text(_statusLabel(package))),
                          if (!expired && !archived)
                            Chip(
                              avatar: const Icon(Icons.schedule, size: 16),
                              label: Text(
                                '${package.daysRemaining()} hari lagi',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Informasi Kuota', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfo(
                        label: 'Total Kuota',
                        value: formatBytes(package.advertisedTotalQuotaBytes),
                      ),
                      const Divider(),
                      _buildInfo(label: 'Pemakaian', value: 'Belum tersedia'),
                      const Divider(),
                      _buildInfo(label: 'Sisa Kuota', value: 'Belum tersedia'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Informasi Paket', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfo(
                        label: 'Tanggal Mulai',
                        value: formatDate(package.startDate),
                      ),
                      const Divider(),
                      _buildInfo(
                        label: 'Tanggal Berakhir',
                        value: formatDate(package.endDate),
                      ),
                      const Divider(),
                      _buildInfo(label: 'Status', value: _statusLabel(package)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (canActivate) ...[
                FilledButton.icon(
                  onPressed: provider.isLoading
                      ? null
                      : () => _setActive(package),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Jadikan Paket Utama'),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => _editPackage(package),
                icon: const Icon(Icons.tune),
                label: const Text('Edit Informasi Paket'),
              ),
              const SizedBox(height: 10),
              if (!archived) ...[
                OutlinedButton.icon(
                  onPressed: provider.isLoading
                      ? null
                      : () => _archivePackage(package),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Arsipkan Paket'),
                ),
                const SizedBox(height: 10),
              ],
              TextButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => _deletePackage(package),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Hapus Paket'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
