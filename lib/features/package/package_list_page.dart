import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_format.dart';
import 'package_provider.dart';

enum _PackageFilter { all, active, expired, archived }

class PackageListPage extends StatefulWidget {
  const PackageListPage({super.key});

  @override
  State<PackageListPage> createState() => _PackageListPageState();
}

class _PackageListPageState extends State<PackageListPage> {
  _PackageFilter _filter = _PackageFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPackages());
  }

  Future<void> _loadPackages() async {
    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null) return;
    await context.read<PackageProvider>().load(userId);
  }

  bool _isArchived(DataPackage p) => p.isArchived;
  bool _isExpired(DataPackage p) => !p.isArchived && p.isExpiredAt();
  bool _isRunning(DataPackage p) => !p.isArchived && !p.isExpiredAt();

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
        final all = [...provider.packages]
          ..sort((a, b) {
            int rank(DataPackage p) =>
                p.status == PackageStatus.active && _isRunning(p) ? 0 : 1;
            return rank(a).compareTo(rank(b));
          });

        final running = all.where(_isRunning).toList();
        final expired = all.where(_isExpired).toList();
        final archived = all.where(_isArchived).toList();

        final visible = switch (_filter) {
          _PackageFilter.all => all,
          _PackageFilter.active => running,
          _PackageFilter.expired => expired,
          _PackageFilter.archived => archived,
        };

        final theme = Theme.of(context);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Daftar Paket',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.circle, size: 10),
                    label: Text('${running.length} Aktif'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kelola paket aktif dan kuota tambahan dengan cermat.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  _filterChip('Semua', all.length, _PackageFilter.all),
                  _filterChip('Aktif', running.length, _PackageFilter.active),
                  _filterChip(
                    'Kedaluwarsa',
                    expired.length,
                    _PackageFilter.expired,
                  ),
                  _filterChip(
                    'Arsip',
                    archived.length,
                    _PackageFilter.archived,
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadPackages,
                child: _buildContent(provider, visible),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filterChip(String label, int count, _PackageFilter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label  $count'),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _buildContent(PackageProvider provider, List<DataPackage> visible) {
    if (provider.isLoading && provider.packages.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
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
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(Icons.sim_card_outlined, size: 56),
                SizedBox(height: 12),
                Text('Belum ada paket pada kategori ini.'),
              ],
            ),
          )
        else
          ...visible.map(_buildPackageCard),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            onTap: provider.isLoading ? null : _openForm,
            leading: const CircleAvatar(child: Icon(Icons.add)),
            title: const Text('Tambah Paket Baru'),
          ),
        ),
      ],
    );
  }

  Widget _buildPackageCard(DataPackage package) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final archived = _isArchived(package);
    final expired = _isExpired(package);
    final isMain = package.status == PackageStatus.active && !expired;

    final String statusLabel;
    final Color statusColor;

    if (archived) {
      statusLabel = 'Diarsipkan';
      statusColor = scheme.outline;
    } else if (expired) {
      statusLabel = 'Kedaluwarsa';
      statusColor = scheme.error;
    } else if (isMain) {
      statusLabel = 'Paket Utama';
      statusColor = scheme.primary;
    } else {
      statusLabel = 'Paket Tambahan';
      statusColor = scheme.secondary;
    }

    final days = package.daysRemaining();
    final remaining = (archived || expired)
        ? 'Berakhir ${formatDate(package.endDate)}'
        : '$days hari lagi (${formatDate(package.endDate)})';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(package),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sim_card, color: statusColor, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          package.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium,
                        ),
                        if ((package.operatorName ?? '').isNotEmpty)
                          Text(
                            package.operatorName!,
                            style: textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(statusLabel),
                    labelStyle: TextStyle(color: statusColor),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    formatBytes(package.advertisedTotalQuotaBytes),
                    style: textTheme.titleLarge,
                  ),
                  const Spacer(),
                  const Icon(Icons.schedule, size: 16),
                  const SizedBox(width: 4),
                  Flexible(child: Text(remaining, textAlign: TextAlign.end)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Mulai ${formatDate(package.startDate)}',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openDetail(package),
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Lihat Rincian'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
