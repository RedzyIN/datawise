import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
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

    if (argument is String) {
      _packageId = argument;
    }
  }

  String _formatBytes(num bytes) {
    final gb = bytes / 1000000000;

    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }

    final mb = bytes / 1000000;
    return '${mb.toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  String _statusLabel(PackageStatus status) {
    switch (status) {
      case PackageStatus.active:
        return 'Paket Utama';
      case PackageStatus.inactive:
        return 'Paket Tambahan';
      case PackageStatus.expired:
        return 'Kedaluwarsa';
      case PackageStatus.archived:
        return 'Diarsipkan';
    }
  }

  Future<void> _editPackage(DataPackage package) async {
    await Navigator.pushNamed(context, Routes.packageForm, arguments: package);
  }

  Future<void> _setActive(DataPackage package) async {
    final userId = context.read<AuthProvider>().currentUser?.uid;

    if (userId == null || package.id == null) return;

    final provider = context.read<PackageProvider>();
    provider.clearError();

    await provider.setActive(userId, package.id!);

    if (!mounted) return;

    if (provider.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(provider.errorMessage!)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Paket utama berhasil diubah.')),
    );
  }

  Future<void> _archivePackage(DataPackage package) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Arsipkan Paket?'),
          content: Text(
            'Paket "${package.packageName}" akan dipindahkan ke arsip. '
            'Kategori, catatan penggunaan, aturan, dan riwayat notifikasi tetap disimpan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Arsipkan'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || package.id == null) return;

    final provider = context.read<PackageProvider>();
    provider.clearError();
    final success = await provider.archivePackage(package.id!, userId);

    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Gagal mengarsipkan paket.'),
        ),
      );
    }
  }

  Future<void> _deletePackage(DataPackage package) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hapus Paket?'),
          content: Text(
            'Paket "${package.packageName}" beserta kategori, catatan penggunaan, '
            'aturan klasifikasi, dan riwayat notifikasinya akan dihapus permanen. '
            'Tindakan ini tidak dapat dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Hapus Permanen'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final userId = context.read<AuthProvider>().currentUser?.uid;

    if (userId == null || package.id == null) return;

    final provider = context.read<PackageProvider>();
    provider.clearError();

    final success = await provider.deletePackage(package.id!, userId);

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Gagal menghapus paket.'),
        ),
      );
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
        DataPackage? package;

        if (_packageId != null) {
          for (final item in provider.packages) {
            if (item.id == _packageId) {
              package = item;
              break;
            }
          }
        }

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

        final currentPackage = package;
        final isActive = currentPackage.status == PackageStatus.active;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Detail Paket'),
            actions: [
              IconButton(
                tooltip: 'Edit paket',
                onPressed: provider.isLoading
                    ? null
                    : () => _editPackage(currentPackage),
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
                        currentPackage.packageName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (currentPackage.operatorName != null &&
                          currentPackage.operatorName!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          currentPackage.operatorName!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Chip(label: Text(_statusLabel(currentPackage.status))),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Informasi Kuota',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfo(
                        label: 'Total Kuota',
                        value: _formatBytes(
                          currentPackage.advertisedTotalQuotaBytes,
                        ),
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

              Text(
                'Informasi Paket',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfo(
                        label: 'Tanggal Mulai',
                        value: _formatDate(currentPackage.startDate),
                      ),
                      const Divider(),
                      _buildInfo(
                        label: 'Tanggal Berakhir',
                        value: _formatDate(currentPackage.endDate),
                      ),
                      const Divider(),
                      _buildInfo(
                        label: 'Status',
                        value: _statusLabel(currentPackage.status),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (!isActive &&
                  currentPackage.status != PackageStatus.expired &&
                  currentPackage.status != PackageStatus.archived)
                FilledButton.icon(
                  onPressed: provider.isLoading
                      ? null
                      : () => _setActive(currentPackage),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Jadikan Paket Utama'),
                ),

              const SizedBox(height: 10),

              OutlinedButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => _editPackage(currentPackage),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Paket'),
              ),

              const SizedBox(height: 10),

              if (currentPackage.status != PackageStatus.archived) ...[
                OutlinedButton.icon(
                  onPressed: provider.isLoading
                      ? null
                      : () => _archivePackage(currentPackage),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Arsipkan Paket'),
                ),
                const SizedBox(height: 10),
              ],

              TextButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => _deletePackage(currentPackage),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Hapus Paket'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
