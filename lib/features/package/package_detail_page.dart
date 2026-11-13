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
  int? _packageId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_packageId != null) return;

    final argument = ModalRoute.of(context)?.settings.arguments;

    if (argument is int) {
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

  String _formatPrice(int? price) {
    if (price == null) return 'Tidak dicantumkan';

    final digits = price.toString();
    final result = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        result.write('.');
      }

      result.write(digits[i]);
    }

    return 'Rp$result';
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

  Future<void> _deletePackage(DataPackage package) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hapus Paket?'),
          content: Text(
            'Paket "${package.name}" akan dihapus. '
            'Tindakan ini tidak dapat dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Hapus'),
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

        final remainingBytes = (package.totalBytes - package.initialUsedBytes)
            .clamp(0, package.totalBytes);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Detail Paket'),
            actions: [
              IconButton(
                tooltip: 'Edit paket',
                onPressed: provider.isLoading
                    ? null
                    : () => _editPackage(package!),
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
                        package.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        package.operator,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Chip(
                        label: Text(
                          package.isActive ? 'Paket Utama' : 'Paket Tambahan',
                        ),
                      ),
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
                        value: _formatBytes(package.totalBytes),
                      ),
                      const Divider(),
                      _buildInfo(
                        label: 'Pemakaian Awal',
                        value: _formatBytes(package.initialUsedBytes),
                      ),
                      const Divider(),
                      _buildInfo(
                        label: 'Sisa Kuota Awal',
                        value: _formatBytes(remainingBytes),
                      ),
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
                        value: _formatDate(package.startDate),
                      ),
                      const Divider(),
                      _buildInfo(
                        label: 'Tanggal Berakhir',
                        value: _formatDate(package.endDate),
                      ),
                      const Divider(),
                      _buildInfo(
                        label: 'Harga',
                        value: _formatPrice(package.price),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (!package.isActive)
                FilledButton.icon(
                  onPressed: provider.isLoading
                      ? null
                      : () => _setActive(package!),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Jadikan Paket Utama'),
                ),

              const SizedBox(height: 10),

              OutlinedButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => _editPackage(package!),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Paket'),
              ),

              const SizedBox(height: 10),

              TextButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => _deletePackage(package!),
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
