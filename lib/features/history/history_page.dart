import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'history_detail_page.dart';
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
  String? _requestedUid;
  bool _hasLoadedCurrentUser = false;

  static const Color _backgroundColor = Color(0xFFE4FBF7);
  static const Color _primaryColor = Color(0xFF00796F);
  static const Color _titleColor = Color(0xFF073B3A);
  static const Color _mutedColor = Color(0xFF66817E);
  static const Color _borderColor = Color(0xFFD7F0EC);

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

      final currentUid = context.read<AuthProvider>().currentUser?.uid;
      if (currentUid != uid) return;

      await context.read<PackageProvider>().load(uid);

      if (!mounted) return;

      final latestUid = context.read<AuthProvider>().currentUser?.uid;

      if (latestUid == uid) {
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
        return const Color(0xFF00796F);
      case PackageStatus.expired:
        return const Color(0xFFCC5555);
      case PackageStatus.archived:
        return const Color(0xFF849492);
      case PackageStatus.active:
        return const Color(0xFF00695C);
    }
  }

  Color _getStatusBackground(PackageStatus status) {
    switch (status) {
      case PackageStatus.inactive:
        return const Color(0xFFE4FBF7);
      case PackageStatus.expired:
        return const Color(0xFFFFEEEE);
      case PackageStatus.archived:
        return const Color(0xFFF0F2F1);
      case PackageStatus.active:
        return const Color(0xFFD7F0EC);
    }
  }

  Future<void> _refreshHistory(String uid) async {
    await context.read<PackageProvider>().load(uid);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final packageProvider = context.watch<PackageProvider>();

    final uid = authProvider.currentUser?.uid;

    if (authProvider.status == AuthStatus.unknown) {
      return _buildStatusView(
        const CircularProgressIndicator(color: _primaryColor),
      );
    }

    if (uid == null) {
      return _buildStatusView(
        const Text(
          'Silakan masuk untuk melihat riwayat paket.',
          style: TextStyle(color: _mutedColor),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (packageProvider.isLoading || !_hasLoadedCurrentUser) {
      return _buildStatusView(
        const CircularProgressIndicator(color: _primaryColor),
      );
    }

    if (packageProvider.errorMessage != null) {
      return _buildStatusView(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Gagal memuat riwayat paket.',
              style: TextStyle(color: _titleColor),
            ),
            const SizedBox(height: 12),
            Text(
              packageProvider.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _mutedColor),
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

    return ColoredBox(
      color: _backgroundColor,
      child: RefreshIndicator(
        color: _primaryColor,
        onRefresh: () => _refreshHistory(uid),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const Text(
              'Riwayat Paket',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: _titleColor,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Daftar paket terdahulu beserta informasi masa berlakunya.',
              style: TextStyle(fontSize: 14, color: _mutedColor),
            ),
            const SizedBox(height: 28),

            if (historyPackages.isEmpty)
              _buildEmptyState()
            else ...[
              Text(
                '${historyPackages.length} paket tersimpan',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _titleColor,
                ),
              ),
              const SizedBox(height: 12),
              ...historyPackages.map(_buildPackageCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusView(Widget child) {
    return ColoredBox(
      color: _backgroundColor,
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
              color: _primaryColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_rounded,
              size: 38,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Belum Ada Riwayat Paket',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: _titleColor,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paket yang sudah tidak aktif, kedaluwarsa, atau diarsipkan akan muncul di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _mutedColor),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor, width: 1),
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _titleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatBytes(package.advertisedTotalQuotaBytes),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              package.operatorName ?? '-',
              style: const TextStyle(fontSize: 14, color: _mutedColor),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: _mutedColor,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Berakhir ${_formatDate(package.endDate)}',
                    style: const TextStyle(fontSize: 12, color: _mutedColor),
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
