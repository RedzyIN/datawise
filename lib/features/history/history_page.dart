import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../shared/widgets/datawise_header.dart';

import 'history_detail_page.dart';
import '../../features/alerts/alert_history_page.dart';
import '../../features/alerts/alert_provider.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/package/package_provider.dart';
import '../../models/data_package.dart';
import '../../models/enums.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  AppPageColors get pal => AppPageColors.of(context);

  String? _requestedUid;
  bool _hasLoadedCurrentUser = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final uid = context.watch<AuthProvider>().currentUser?.uid;

    if (uid == _requestedUid) return;

    _requestedUid = uid;
    _hasLoadedCurrentUser = false;

    if (uid == null) return;

    Future.microtask(() async {
      if (!mounted) return;

      final auth = context.read<AuthProvider>();
      final packages = context.read<PackageProvider>();
      final alerts = context.read<AlertProvider>();

      if (auth.currentUser?.uid != uid) return;

      await packages.load(uid);
      await alerts.load(uid);

      if (!mounted) return;

      if (auth.currentUser?.uid == uid) {
        setState(() {
          _hasLoadedCurrentUser = true;
        });
      }
    });
  }

  List<DataPackage> _getHistoryPackages(List<DataPackage> packages) {
    final historyPackages = packages.where((package) {
      return package.status == PackageStatus.inactive ||
          package.status == PackageStatus.expired ||
          package.status == PackageStatus.archived;
    }).toList();

    historyPackages.sort((a, b) {
      final dateComparison = b.endDate.compareTo(a.endDate);

      if (dateComparison != 0) {
        return dateComparison;
      }

      return b.createdAt.compareTo(a.createdAt);
    });

    return historyPackages;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1000) return '$bytes B';

    const units = ['KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unitIndex = -1;

    while (size >= 1000 && unitIndex < units.length - 1) {
      size /= 1000;
      unitIndex++;
    }

    final formattedSize = size % 1 == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);

    return '$formattedSize ${units[unitIndex]}';
  }

  String _getStatusLabel(PackageStatus status) {
    switch (status) {
      case PackageStatus.inactive:
        return 'Belum Aktif';
      case PackageStatus.expired:
        return 'Kedaluwarsa';
      case PackageStatus.archived:
        return 'Diarsipkan';
      case PackageStatus.active:
        return 'Aktif';
    }
  }

  Color _getStatusColor(PackageStatus status) {
    switch (status) {
      case PackageStatus.inactive:
        return pal.primary;
      case PackageStatus.expired:
        return pal.danger;
      case PackageStatus.archived:
        return pal.muted;
      case PackageStatus.active:
        return pal.primaryDeep;
    }
  }

  Color _getStatusBackground(PackageStatus status) {
    switch (status) {
      case PackageStatus.inactive:
        return pal.mint;
      case PackageStatus.expired:
        return pal.dangerBg;
      case PackageStatus.archived:
        return pal.surfaceAlt;
      case PackageStatus.active:
        return pal.line;
    }
  }

  Future<void> _refreshHistory(String uid) async {
    final packages = context.read<PackageProvider>();
    final alerts = context.read<AlertProvider>();

    await packages.load(uid);
    await alerts.load(uid);
  }

  /// Membuka Notification Center, lalu memperbarui indikator lonceng.
  Future<void> _openNotifications() async {
    final uid = context.read<AuthProvider>().currentUser?.uid;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlertHistoryPage()),
    );

    if (!mounted || uid == null) return;

    await context.read<AlertProvider>().load(uid);
  }

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    final authProvider = context.watch<AuthProvider>();
    final packageProvider = context.watch<PackageProvider>();

    final uid = authProvider.currentUser?.uid;
    final alerts = context.watch<AlertProvider>();

    return ColoredBox(
      color: pal.background,
      child: Column(
        children: [
          // Header global yang sama dengan Dashboard. Sebelumnya halaman ini
          // tidak memiliki header sehingga hanya judul konten yang terlihat.
          DatawiseHeader(
            pageLabel: 'Riwayat',
            unreadCount: alerts.unreadCount,
            onBell: _openNotifications,
          ),
          Expanded(
            child: _buildContent(
              pal: pal,
              authProvider: authProvider,
              packageProvider: packageProvider,
              uid: uid,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent({
    required AppPageColors pal,
    required AuthProvider authProvider,
    required PackageProvider packageProvider,
    required String? uid,
  }) {
    if (authProvider.status == AuthStatus.unknown) {
      return _buildStatusView(CircularProgressIndicator(color: pal.primary));
    }

    if (uid == null) {
      return _buildStatusView(
        Text(
          'Silakan masuk untuk melihat riwayat paket.',
          style: TextStyle(color: pal.muted),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (packageProvider.isLoading || !_hasLoadedCurrentUser) {
      return _buildStatusView(CircularProgressIndicator(color: pal.primary));
    }

    if (packageProvider.errorMessage != null) {
      return _buildStatusView(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Gagal memuat riwayat paket.',
              style: TextStyle(color: pal.ink),
            ),
            const SizedBox(height: 12),
            Text(
              packageProvider.errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.muted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                setState(() {
                  _hasLoadedCurrentUser = false;
                });

                await _refreshHistory(uid);

                if (!mounted) return;

                setState(() {
                  _hasLoadedCurrentUser = true;
                });
              },
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }

    final historyPackages = _getHistoryPackages(packageProvider.packages);

    return RefreshIndicator(
      color: pal.primary,
      onRefresh: () => _refreshHistory(uid),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Riwayat Paket',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: pal.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Daftar paket terdahulu beserta informasi masa berlakunya.',
            style: TextStyle(fontSize: 14, color: pal.muted),
          ),
          const SizedBox(height: 24),

          if (historyPackages.isEmpty)
            _buildEmptyState()
          else ...[
            Text(
              '${historyPackages.length} paket tersimpan',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: pal.ink,
              ),
            ),
            const SizedBox(height: 12),
            ...historyPackages.map(_buildPackageCard),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusView(Widget child) {
    return ColoredBox(
      color: pal.background,
      child: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: pal.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded, size: 38, color: pal.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Belum Ada Riwayat Paket',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: pal.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paket yang sudah tidak aktif, kedaluwarsa, atau diarsipkan akan muncul di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: pal.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(DataPackage package) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HistoryDetailPage(package: package),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.line, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    package.packageName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: pal.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatBytes(package.advertisedTotalQuotaBytes),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: pal.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              package.operatorName ?? '-',
              style: TextStyle(fontSize: 14, color: pal.muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 14, color: pal.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Berakhir ${_formatDate(package.endDate)}',
                    style: TextStyle(fontSize: 12, color: pal.muted),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusBackground(package.status),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _getStatusLabel(package.status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(package.status),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
