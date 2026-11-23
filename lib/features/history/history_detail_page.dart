import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';

import '../../models/models.dart';
import '../../repositories/quota_category_repository.dart';
import '../../repositories/usage_repository.dart';

class HistoryDetailPage extends StatefulWidget {
  final DataPackage package;

  const HistoryDetailPage({super.key, required this.package});

  @override
  State<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends State<HistoryDetailPage> {
  AppPageColors get pal => AppPageColors.of(context);

  late Future<_HistoryDetailData> _dataFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataFuture = _loadData();
  }

  Future<_HistoryDetailData> _loadData() async {
    final packageId = widget.package.id;

    if (packageId == null || packageId.isEmpty) {
      throw Exception('ID paket tidak ditemukan.');
    }

    final usageRepository = context.read<UsageRepository>();
    final categoryRepository = context.read<QuotaCategoryRepository>();

    final records = await usageRepository.getRecords(packageId);
    final allocations = await usageRepository.getAllocationsByPackage(
      packageId,
    );
    final categories = await categoryRepository.getByPackage(packageId);

    // DEVICE_TOTAL tidak dihitung karena dapat tumpang tindih
    // dengan APP_USAGE. Ringkasan menggunakan allocations.
    final categoryNames = <String, String>{
      for (final category in categories)
        if (category.id != null) category.id!: category.categoryName,
    };

    final categoryTotals = <String, int>{};
    final recordTotals = <String, int>{};

    int unclassifiedBytes = 0;

    for (final allocation in allocations) {
      final categoryId = allocation.quotaCategoryId;

      if (categoryId == null) {
        unclassifiedBytes += allocation.allocatedBytes;
      } else {
        categoryTotals.update(
          categoryId,
          (value) => value + allocation.allocatedBytes,
          ifAbsent: () => allocation.allocatedBytes,
        );
      }

      recordTotals.update(
        allocation.usageRecordId,
        (value) => value + allocation.allocatedBytes,
        ifAbsent: () => allocation.allocatedBytes,
      );
    }

    final usageDetails = records.where((record) {
      return record.id != null &&
          recordTotals.containsKey(record.id) &&
          record.recordScope != UsageRecordScope.deviceTotal;
    }).toList();

    usageDetails.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    final totalUsedBytes = allocations.fold<int>(
      0,
      (total, allocation) => total + allocation.allocatedBytes,
    );

    return _HistoryDetailData(
      categoryNames: categoryNames,
      categoryTotals: categoryTotals,
      recordTotals: recordTotals,
      usageDetails: usageDetails,
      totalUsedBytes: totalUsedBytes,
      unclassifiedBytes: unclassifiedBytes,
    );
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

    final formatted = size % 1 == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);

    return '$formatted ${units[unitIndex]}';
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

  String _formatDateTime(DateTime date) {
    final dateText = _formatDate(date);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$dateText, $hour:$minute';
  }

  String _statusLabel(PackageStatus status) {
    switch (status) {
      case PackageStatus.active:
        return 'Aktif';
      case PackageStatus.inactive:
        return 'Tidak Aktif';
      case PackageStatus.expired:
        return 'Kedaluwarsa';
      case PackageStatus.archived:
        return 'Diarsipkan';
    }
  }

  Color _statusColor(PackageStatus status) {
    switch (status) {
      case PackageStatus.active:
        return pal.success;
      case PackageStatus.inactive:
        return pal.muted;
      case PackageStatus.expired:
        return pal.danger;
      case PackageStatus.archived:
        return pal.muted;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Scaffold(
      backgroundColor: pal.background,
      appBar: AppBar(
        backgroundColor: pal.surface,
        foregroundColor: pal.ink,
        elevation: 0,
        title: Text(
          'Detail Riwayat',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: pal.ink,
          ),
        ),
      ),
      body: FutureBuilder<_HistoryDetailData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: pal.primary));
          }

          if (snapshot.hasError) {
            return _buildErrorState();
          }

          final data = snapshot.data;

          if (data == null) {
            return _buildErrorState();
          }

          return _buildContent(data);
        },
      ),
    );
  }

  Widget _buildContent(_HistoryDetailData data) {
    final package = widget.package;
    final statusColor = _statusColor(package.status);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _buildPackageCard(package, statusColor),
        const SizedBox(height: 20),
        _buildUsageSummary(data),
        const SizedBox(height: 20),
        _buildCategorySection(data),
        const SizedBox(height: 20),
        _buildUsageHistorySection(data),
      ],
    );
  }

  Widget _buildPackageCard(DataPackage package, Color statusColor) {
    return _buildCard(
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
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: pal.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildStatusChip(_statusLabel(package.status), statusColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            package.operatorName ?? 'Operator tidak diketahui',
            style: TextStyle(fontSize: 14, color: pal.muted),
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
            Icons.data_usage_rounded,
            'Total kuota',
            _formatBytes(package.advertisedTotalQuotaBytes),
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            Icons.calendar_today_rounded,
            'Tanggal mulai',
            _formatDate(package.startDate),
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            Icons.event_rounded,
            'Tanggal berakhir',
            _formatDate(package.endDate),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageSummary(_HistoryDetailData data) {
    final totalQuota = widget.package.advertisedTotalQuotaBytes;
    final percentage = totalQuota > 0
        ? (data.totalUsedBytes / totalQuota * 100)
        : 0.0;
    final progress = (percentage / 100).clamp(0.0, 1.0).toDouble();

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ringkasan Pemakaian',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: pal.ink,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _formatBytes(data.totalUsedBytes),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: pal.primary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'dari ${_formatBytes(totalQuota)} kuota paket',
            style: TextStyle(fontSize: 13, color: pal.muted),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: pal.line,
              valueColor: AlwaysStoppedAnimation<Color>(pal.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${percentage.toStringAsFixed(1)}% dari total kuota',
            style: TextStyle(fontSize: 12, color: pal.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(_HistoryDetailData data) {
    final categoryEntries = data.categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pemakaian per Kategori',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: pal.ink,
            ),
          ),
          const SizedBox(height: 18),
          if (categoryEntries.isEmpty && data.unclassifiedBytes == 0)
            _buildSectionEmpty('Belum ada data pemakaian kategori.')
          else ...[
            ...categoryEntries.map((entry) {
              final categoryName =
                  data.categoryNames[entry.key] ?? 'Kategori lainnya';

              return _buildCategoryItem(
                categoryName,
                entry.value,
                data.totalUsedBytes,
              );
            }),
            if (data.unclassifiedBytes > 0)
              _buildCategoryItem(
                'Belum diklasifikasikan',
                data.unclassifiedBytes,
                data.totalUsedBytes,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryItem(String name, int usedBytes, int totalBytes) {
    final percentage = totalBytes > 0 ? usedBytes / totalBytes : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: pal.ink,
                  ),
                ),
              ),
              Text(
                _formatBytes(usedBytes),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: pal.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: percentage.clamp(0.0, 1.0).toDouble(),
              minHeight: 7,
              backgroundColor: pal.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(pal.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageHistorySection(_HistoryDetailData data) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catatan Pemakaian',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: pal.ink,
            ),
          ),
          const SizedBox(height: 16),
          if (data.usageDetails.isEmpty)
            _buildSectionEmpty('Belum ada catatan pemakaian.')
          else
            ...data.usageDetails.map((record) {
              final usedBytes = data.recordTotals[record.id] ?? 0;

              final description =
                  record.recordScope == UsageRecordScope.manualTotal
                  ? 'Input manual'
                  : record.appName ??
                        record.appPackageName ??
                        'Pemakaian aplikasi';

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: pal.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.data_usage_rounded,
                        size: 19,
                        color: pal.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: pal.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(record.recordedAt),
                            style: TextStyle(fontSize: 11, color: pal.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatBytes(usedBytes),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: pal.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: pal.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 13, color: pal.muted)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: pal.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.line),
      ),
      child: child,
    );
  }

  Widget _buildSectionEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: pal.muted),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 42, color: pal.muted),
            const SizedBox(height: 14),
            Text(
              'Gagal memuat detail riwayat.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: pal.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Periksa koneksi database, lalu coba kembali.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: pal.muted),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: _retry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class _HistoryDetailData {
  final Map<String, String> categoryNames;
  final Map<String, int> categoryTotals;
  final Map<String, int> recordTotals;
  final List<UsageRecord> usageDetails;
  final int totalUsedBytes;
  final int unclassifiedBytes;

  const _HistoryDetailData({
    required this.categoryNames,
    required this.categoryTotals,
    required this.recordTotals,
    required this.usageDetails,
    required this.totalUsedBytes,
    required this.unclassifiedBytes,
  });
}
