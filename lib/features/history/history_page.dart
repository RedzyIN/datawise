import 'package:flutter/material.dart';

import '../../models/data_package.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.packages = const []});

  final List<DataPackage> packages;

  bool _isExpired(DataPackage package) {
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final endDate = DateTime(
      package.endDate.year,
      package.endDate.month,
      package.endDate.day,
    );

    return endDate.isBefore(today);
  }

  List<DataPackage> _getExpiredPackages() {
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
    if (bytes < 1024) return '$bytes B';

    const units = ['KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unitIndex = -1;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final formattedSize = size % 1 == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);

    return '$formattedSize ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final expiredPackages = _getExpiredPackages();
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Riwayat Paket',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Daftar paket yang telah kedaluwarsa.',
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),

        if (expiredPackages.isEmpty)
          _buildEmptyState(context)
        else ...[
          Text(
            '${expiredPackages.length} paket kedaluwarsa',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          ...expiredPackages.map(
            (package) => _buildPackageCard(context, package),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum Ada Riwayat Paket',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Paket yang sudah kedaluwarsa akan muncul di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(BuildContext context, DataPackage package) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    package.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Kedaluwarsa',
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              package.operator,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            _buildInfoRow('Total kuota', _formatBytes(package.totalBytes)),
            const SizedBox(height: 10),
            _buildInfoRow('Tanggal berakhir', _formatDate(package.endDate)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
