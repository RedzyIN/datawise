import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_format.dart';
import 'package_provider.dart';
import 'package_theme.dart';

enum _Tab { all, active, expired }

class PackageListPage extends StatefulWidget {
  const PackageListPage({super.key, this.showHeader = true});

  /// Set false jika shell/halaman induk sudah punya header DATAWISE sendiri.
  final bool showHeader;

  @override
  State<PackageListPage> createState() => _PackageListPageState();
}

class _PackageListPageState extends State<PackageListPage> {
  _Tab _tab = _Tab.all;

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
        final history = all.where((p) => !_isRunning(p)).toList();

        return ColoredBox(
          color: PkgPalette.of(context).bg,
          child: Column(
            children: [
              if (widget.showHeader) _brandHeader(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadPackages,
                  child: _body(provider, all, running, history),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _brandHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DATAWISE',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: PkgPalette.of(context).primary,
                    ),
                  ),
                  Text(
                    'Paket',
                    style: TextStyle(
                      fontSize: 13,
                      color: PkgPalette.of(context).text,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(
                Icons.notifications_none,
                color: PkgPalette.of(context).text,
                size: 26,
              ),
            ),
            const SizedBox(width: 2),
            const PkgAvatar(),
          ],
        ),
      ),
    );
  }

  Widget _body(
    PackageProvider provider,
    List<DataPackage> all,
    List<DataPackage> running,
    List<DataPackage> history,
  ) {
    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              'Daftar Paket',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: PkgPalette.of(context).text,
              ),
            ),
          ),
          PkgPill('${running.length} Aktif', dot: true),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        'Kelola paket aktif dan kuota tambahan dengan cermat.',
        style: TextStyle(color: PkgPalette.of(context).muted, fontSize: 12),
      ),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tabPill('Semua', all.length, _Tab.all),
            const SizedBox(width: 8),
            _tabPill('Aktif', running.length, _Tab.active),
            const SizedBox(width: 8),
            _tabPill('Kedaluwarsa', history.length, _Tab.expired),
          ],
        ),
      ),
      const SizedBox(height: 14),
    ];

    if (provider.isLoading && provider.packages.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (provider.errorMessage != null && provider.packages.isEmpty) {
      children.addAll([
        const SizedBox(height: 60),
        Center(child: Text(provider.errorMessage!)),
        Center(
          child: TextButton(
            onPressed: _loadPackages,
            child: const Text('Coba lagi'),
          ),
        ),
      ]);
    } else {
      if (provider.errorMessage != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              provider.errorMessage!,
              style: TextStyle(color: PkgPalette.of(context).danger),
            ),
          ),
        );
      }

      final showRunning = _tab != _Tab.expired;
      final showHistory = _tab != _Tab.active;

      if (showRunning) {
        if (running.isEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Belum ada paket aktif.',
                  style: TextStyle(color: PkgPalette.of(context).muted),
                ),
              ),
            ),
          );
        }
        for (final p in running) {
          children.add(_runningCard(p));
          children.add(const SizedBox(height: 14));
        }
        children.add(_addCard(provider.isLoading));
      }

      if (showHistory) {
        children.add(const SizedBox(height: 22));
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Expanded + ellipsis agar judul menyusut pada layar sempit
              // alih-alih mendorong "Lihat Semua" keluar dari Row.
              Expanded(
                child: Text(
                  'Riwayat Paket',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: PkgPalette.of(context).text,
                  ),
                ),
              ),
              if (_tab != _Tab.expired)
                GestureDetector(
                  onTap: () => setState(() => _tab = _Tab.expired),
                  child: Text(
                    'Lihat Semua',
                    style: TextStyle(
                      color: PkgPalette.of(context).primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        );
        children.add(const SizedBox(height: 10));

        if (history.isEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Belum ada riwayat paket.',
                style: TextStyle(color: PkgPalette.of(context).muted),
              ),
            ),
          );
        }

        final shown = _tab == _Tab.all ? history.take(3).toList() : history;
        for (final p in shown) {
          children.add(_historyTile(p));
          children.add(const SizedBox(height: 10));
        }
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: children,
    );
  }

  Widget _tabPill(String label, int count, _Tab value) {
    final selected = _tab == value;

    return GestureDetector(
      onTap: () => setState(() => _tab = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? PkgPalette.of(context).primary
              : PkgPalette.of(context).card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected
                    ? PkgPalette.of(context).onPrimary
                    : PkgPalette.of(context).text,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? PkgPalette.of(context).field
                    : PkgPalette.of(context).chip,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  color: selected
                      ? PkgPalette.of(context).primary
                      : PkgPalette.of(context).muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runningCard(DataPackage p) {
    final isMain = p.status == PackageStatus.active;
    final frac = timeLeftFraction(p);
    final (value, unit) = splitBytes(p.advertisedTotalQuotaBytes);

    return PkgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PkgIconBox(Icons.sim_card, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.packageName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PkgPalette.of(context).text,
                      ),
                    ),
                    if ((p.operatorName ?? '').isNotEmpty)
                      Text(
                        p.operatorName!,
                        style: TextStyle(
                          fontSize: 13,
                          color: PkgPalette.of(context).muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              PkgStatusPill(p),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PkgPalette.of(context).field,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: PkgPalette.of(context).primary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '$unit total',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: PkgPalette.of(context).muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.trending_up,
                                size: 16,
                                color: PkgPalette.of(context).primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Sisa waktu ${(frac * 100).round()}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: PkgPalette.of(context).primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 6,
                    backgroundColor: PkgPalette.of(context).chip,
                    color: PkgPalette.of(context).primary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 16,
                      color: PkgPalette.of(context).muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Masa Aktif',
                      style: TextStyle(
                        color: PkgPalette.of(context).muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p.daysRemaining()} hari lagi (${formatDate(p.endDate)})',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: PkgPalette.of(context).text,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: PkgPalette.of(context).primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMain ? 'Paket utama aktif' : 'Paket tambahan',
                  style: TextStyle(
                    color: PkgPalette.of(context).text,
                    fontSize: 13,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openDetail(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: PkgPalette.of(context).chip,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Lihat Rincian',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: PkgPalette.of(context).primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: PkgPalette.of(context).primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addCard(bool loading) {
    return GestureDetector(
      onTap: loading ? null : _openForm,
      child: PkgCard(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: PkgPalette.of(context).accent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add,
                color: PkgPalette.of(context).primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Tambah Paket Baru',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: PkgPalette.of(context).primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(DataPackage p) {
    return GestureDetector(
      onTap: () => _openDetail(p),
      child: PkgCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            PkgIconBox(
              p.isArchived ? Icons.archive_outlined : Icons.event_busy_outlined,
              size: 38,
              bg: PkgPalette.of(context).chip,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: PkgPalette.of(context).text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatBytes(p.advertisedTotalQuotaBytes)} • '
                    '${formatDate(p.endDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: PkgPalette.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PkgStatusPill(p),
          ],
        ),
      ),
    );
  }
}
