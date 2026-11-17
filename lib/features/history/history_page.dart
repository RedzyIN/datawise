import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/package/package_provider.dart';
import '../../models/data_package.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String? _requestedUid;
  bool _hasLoadedCurrentUser = false;

  static const Color _backgroundColor = Color(0xFFF4F7FC);
  static const Color _primaryColor = Color(0xFF287DBA);
  static const Color _titleColor = Color(0xFF20364A);
  static const Color _mutedColor = Color(0xFF8494A5);
  static const Color _borderColor = Color(0xFFE0E8F0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final authProvider = context.watch<AuthProvider>();
    final uid = authProvider.currentUser?.uid;

    if (uid != _requestedUid) {
      _requestedUid = uid;
      _hasLoadedCurrentUser = false;

      if (uid != null) {
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
    }
  }

  bool _isExpired(DataPackage package) {
    return !package.isArchived && package.isExpiredAt();
  }

  List<DataPackage> _getExpiredPackages(List<DataPackage> packages) {
    final expiredPackages = packages.where(_isExpired).toList();

    expiredPackages.sort((a, b) {
      final dateComparison = b.endDate.compareTo(a.endDate);

      if (dateComparison != 0) {
        return dateComparison;
      }

      return b.createdAt.compareTo(a.createdAt);
    });

    return expiredPackages;
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

                await context.read<PackageProvider>().load(uid);

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

    final expiredPackages = _getExpiredPackages(packageProvider.packages);

    return ColoredBox(
      color: _backgroundColor,
      child: ListView(
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
            'Daftar paket yang telah kedaluwarsa.',
            style: TextStyle(fontSize: 14, color: _mutedColor),
          ),
          const SizedBox(height: 28),
          if (expiredPackages.isEmpty)
            _buildEmptyState()
          else ...[
            Text(
              '${expiredPackages.length} paket kedaluwarsa',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _titleColor,
              ),
            ),
            const SizedBox(height: 16),
            ...expiredPackages.map((package) => _buildPackageCard(package)),
          ],
        ],
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
            'Paket yang sudah kedaluwarsa akan muncul di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _mutedColor),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(DataPackage package) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          const SizedBox(height: 16),
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
                  color: const Color(0xFFFFEEEE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Kedaluwarsa',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCC5555),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
