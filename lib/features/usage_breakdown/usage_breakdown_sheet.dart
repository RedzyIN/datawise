import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../models/models.dart';
import '../../services/usage_breakdown_service.dart';
import 'usage_breakdown_provider.dart';
import 'usage_format.dart';

const _teal = Color(0xFF00796F);
const _mint = Color(0xFFE4FBF7);
const _ink = Color(0xFF073B3A);
const _muted = Color(0xFF66817E);
const _line = Color(0xFFD7F0EC);

String _shareLabel(double share) {
  final percent = share * 100;
  if (percent <= 0) return '0%';
  if (percent < 1) return '<1%';
  return '${percent.round()}%';
}

class UsageBreakdownSheet extends StatefulWidget {
  const UsageBreakdownSheet({super.key, required this.package});

  final DataPackage package;

  @override
  State<UsageBreakdownSheet> createState() => _UsageBreakdownSheetState();
}

class _UsageBreakdownSheetState extends State<UsageBreakdownSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    await context.read<UsageBreakdownProvider>().load(widget.package);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UsageBreakdownProvider>();
    final breakdown = provider.breakdown;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Detail Aplikasi',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang',
                    onPressed: provider.isLoading ? null : _load,
                    icon: const Icon(Icons.refresh, color: _teal),
                  ),
                ],
              ),
              Text(
                breakdown == null
                    ? 'Pemakaian hari ini'
                    : 'Pemakaian ${formatDate(breakdown.day)}',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              Flexible(child: _content(provider, breakdown)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(UsageBreakdownProvider provider, UsageBreakdown? breakdown) {
    if (provider.isLoading && breakdown == null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }

    if (provider.errorMessage != null && breakdown == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              provider.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            TextButton(
              onPressed: _load,
              child: const Text('Coba lagi', style: TextStyle(color: _teal)),
            ),
          ],
        ),
      );
    }

    if (breakdown == null) return const SizedBox.shrink();

    return ListView(
      shrinkWrap: true,
      children: [
        _summaryCard(breakdown),
        const SizedBox(height: 10),
        if (breakdown.manualMode)
          _manualNotice()
        else ...[
          if (!breakdown.hasApps) _emptyState(),
          for (final app in breakdown.apps) _appRow(app),
        ],
        if (breakdown.deviceTotalBytes > 0) ...[
          const SizedBox(height: 10),
          _qualityCard(breakdown),
        ],
        const SizedBox(height: 10),
        const Text(
          'Angka berasal dari usage_records (statistik Android) dan bersifat '
          'estimasi, bukan catatan resmi operator.',
          style: TextStyle(color: _muted, fontSize: 10),
        ),
      ],
    );
  }

  Widget _summaryCard(UsageBreakdown breakdown) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TOTAL DARI APLIKASI',
            style: TextStyle(color: _muted, fontSize: 9, letterSpacing: 0.6),
          ),
          const SizedBox(height: 4),
          Text(
            breakdown.manualMode
                ? '—'
                : formatUsageBytes(breakdown.appTotalBytes),
            style: const TextStyle(
              color: _ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _mint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  breakdown.hasApps
                      ? '${breakdown.apps.length} aplikasi'
                      : 'Belum ada rincian',
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (breakdown.lastUpdatedAt != null)
                Text(
                  'Diperbarui '
                  '${breakdown.lastUpdatedAt!.hour.toString().padLeft(2, '0')}:'
                  '${breakdown.lastUpdatedAt!.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: _muted, fontSize: 9),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _appRow(AppUsageItem app) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _mint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              app.appName.isEmpty ? '?' : app.appName[0].toUpperCase(),
              style: const TextStyle(
                color: _teal,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatUsageBytes(app.totalBytes),
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  app.appPackageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 9),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: app.share.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: _line,
                    valueColor: const AlwaysStoppedAnimation(_teal),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_shareLabel(app.share)} dari pemakaian aplikasi',
                  style: const TextStyle(color: _muted, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qualityCard(UsageBreakdown breakdown) {
    final difference = breakdown.differenceBytes ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _mint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pemakaian aplikasi: ${formatUsageBytes(breakdown.appTotalBytes)}',
                  style: const TextStyle(color: _ink, fontSize: 10),
                ),
              ),
              Text(
                'Perangkat: ${formatUsageBytes(breakdown.deviceTotalBytes)}',
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          ),
          if (difference != 0) ...[
            const SizedBox(height: 4),
            Text(
              difference > 0
                  ? 'Selisih ${formatUsageBytes(difference)} belum terpetakan ke '
                        'aplikasi. Ini informasi kualitas data, bukan kuota '
                        'tambahan.'
                  : 'Jumlah aplikasi melebihi agregat perangkat sebesar '
                        '${formatUsageBytes(-difference)}. Angka tetap estimasi.',
              style: const TextStyle(color: _muted, fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }

  Widget _manualNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF4D7AD)),
      ),
      child: const Text(
        'Hari ini memakai input manual, jadi nama aplikasi tidak tersedia. '
        'Rincian per aplikasi hanya muncul saat pemantauan otomatis aktif.',
        style: TextStyle(color: _ink, fontSize: 10),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: const Column(
        children: [
          Icon(Icons.apps_rounded, color: _muted, size: 34),
          SizedBox(height: 8),
          Text(
            'Belum ada catatan per aplikasi hari ini',
            style: TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Pastikan izin Usage Access aktif dan paket sedang dipakai untuk '
            'akses data seluler.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}
