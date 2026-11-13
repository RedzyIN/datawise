import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_provider.dart';

class PackageListPage extends StatefulWidget {
  const PackageListPage({super.key});

  @override
  State<PackageListPage> createState() => _PackageListPageState();
}

class _PackageListPageState extends State<PackageListPage> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPackages();
    });
  }

  Future<void> _loadPackages() async {
    final userId = context.read<AuthProvider>().currentUser?.uid;

    if (userId == null) return;

    await context.read<PackageProvider>().load(userId);
  }

  String _formatBytes(int bytes) {
    final gb = bytes / 1000000000;
    if (gb >= 1) return '${gb.toStringAsFixed(2)} GB';

    final mb = bytes / 1000000;
    return '${mb.toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  bool _isExpired(DataPackage package) {
    final today = DateUtils.dateOnly(DateTime.now());
    final endDate = DateUtils.dateOnly(package.endDate);

    return endDate.isBefore(today);
  }

  Future<void> _openForm() async {
    await Navigator.pushNamed(context, Routes.packageForm);
    if (mounted) await _loadPackages();
  }

  Future<void> _openDetail(DataPackage package) async {
    if (package.id == null) return;

    await Navigator.pushNamed(
      context,
      Routes.packageDetail,
      arguments: package.id,
    );

    if (mounted) await _loadPackages();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PackageProvider>(
      builder: (context, provider, child) {
        final activePackages = provider.packages
            .where((p) => !_isExpired(p))
            .toList();

        final expiredPackages = provider.packages.where(_isExpired).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Daftar Paket',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: provider.isLoading ? null : _openForm,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah'),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadPackages,
                child: _buildContent(provider, activePackages, expiredPackages),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(
    PackageProvider provider,
    List<DataPackage> activePackages,
    List<DataPackage> expiredPackages,
  ) {
    if (provider.isLoading && provider.packages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.packages.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Center(child: Text(provider.errorMessage!)),
          Center(
            child: TextButton(
              onPressed: _loadPackages,
              child: const Text('Coba lagi'),
            ),
          ),
        ],
      );
    }

    if (provider.packages.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.sim_card_outlined, size: 56),
          SizedBox(height: 12),
          Center(child: Text('Belum ada paket internet')),
          Center(child: Text('Tekan Tambah untuk memasukkan paket.')),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (provider.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              provider.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),

        _buildSection(title: 'Paket Aktif/Berjalan', packages: activePackages),

        const SizedBox(height: 24),

        _buildSection(title: 'Paket Kedaluwarsa', packages: expiredPackages),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List<DataPackage> packages,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title (${packages.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),

        if (packages.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Belum ada paket.'),
          )
        else
          ...packages.map(_buildPackageCard),
      ],
    );
  }

  Widget _buildPackageCard(DataPackage package) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _openDetail(package),
        leading: Icon(
          Icons.sim_card,
          color: package.isActive ? colorScheme.primary : colorScheme.outline,
          size: 32,
        ),
        title: Text(package.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(package.operator),
            Text(
              '${_formatBytes(package.totalBytes)} • '
              '${_formatDate(package.startDate)} - '
              '${_formatDate(package.endDate)}',
            ),
            if (package.isActive)
              Text('Paket utama', style: TextStyle(color: colorScheme.primary)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        isThreeLine: true,
      ),
    );
  }
}
