import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/usage_breakdown_service.dart';
import '../package/package_format.dart';
import '../package/package_theme.dart';
import 'usage_breakdown_provider.dart';
import 'usage_format.dart';

String _shareLabel(double share) {
  final percent = share * 100;
  if (percent <= 0) return '0%';
  if (percent < 1) return '<1%';
  return '${percent.round()}%';
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// Rincian pemakaian per aplikasi.
///
/// Tampilan memakai palet, kartu, dan tipografi yang sama dengan Dashboard
/// (`AppPageColors`) agar Light Mode dan Dark Mode tetap konsisten.
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

  /// Membuka pengaturan Usage Access Android, lalu memuat ulang rincian.
  Future<void> _openUsageAccessSettings() async {
    await context.read<UsageBreakdownProvider>().openUsageAccessSettings();
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UsageBreakdownProvider>();
    final breakdown = provider.breakdown;
    final pal = AppPageColors.of(context);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(provider, breakdown, pal),
              const SizedBox(height: 10),
              Flexible(child: _content(provider, breakdown, pal)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    UsageBreakdownProvider provider,
    UsageBreakdown? breakdown,
    AppPageColors pal,
  ) {
    return Row(
      children: [
        const PkgIconBox(Icons.apps_rounded, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detail Aplikasi',
                style: TextStyle(
                  color: pal.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                breakdown == null
                    ? 'Pemakaian hari ini'
                    : 'Pemakaian ${formatDate(breakdown.day)} · estimasi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: pal.muted, fontSize: 10.5),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: provider.isLoading ? null : _load,
          icon: Icon(Icons.refresh_rounded, color: pal.primary),
        ),
      ],
    );
  }

  Widget _content(
    UsageBreakdownProvider provider,
    UsageBreakdown? breakdown,
    AppPageColors pal,
  ) {
    if (provider.isLoading && breakdown == null) {
      return ListView(
        shrinkWrap: true,
        children: [
          _card(
            pal,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: pal.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Memuat rincian aplikasi…',
                  style: TextStyle(color: pal.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (provider.errorMessage != null && breakdown == null) {
      return ListView(
        shrinkWrap: true,
        children: [
          _card(
            pal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: pal.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rincian aplikasi gagal dimuat',
                        style: TextStyle(
                          color: pal.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  provider.errorMessage!,
                  style: TextStyle(
                    color: pal.muted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _load,
                    style: FilledButton.styleFrom(
                      backgroundColor: pal.primary,
                      foregroundColor: pal.onPrimary,
                    ),
                    child: const Text('Coba lagi'),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (breakdown == null) return const SizedBox.shrink();

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 4),
      children: [
        if (provider.hasPermission == false) ...[
          _permissionCard(pal),
          const SizedBox(height: 10),
        ],
        _summaryCard(breakdown, pal),
        const SizedBox(height: 10),
        if (breakdown.manualMode)
          _noticeCard(
            pal,
            icon: Icons.edit_note,
            text:
                'Hari ini memakai input manual, jadi nama aplikasi tidak '
                'tersedia. Rincian per aplikasi hanya muncul saat pemantauan '
                'otomatis aktif.',
          )
        else if (!breakdown.hasApps && provider.hasPermission != false)
          _emptyState(pal)
        else ...[
          _sectionLabel(breakdown, pal),
          for (final app in breakdown.apps) ...[
            const SizedBox(height: 8),
            _appCard(app, provider, pal),
          ],
        ],
        if (breakdown.deviceTotalBytes > 0) ...[
          const SizedBox(height: 10),
          _qualityCard(breakdown, pal),
        ],
        const SizedBox(height: 10),
        Text(
          'Angka berasal dari usage_records (statistik Android) dan bersifat '
          'estimasi, bukan catatan resmi operator.',
          style: TextStyle(color: pal.muted, fontSize: 10, height: 1.35),
        ),
      ],
    );
  }

  Widget _summaryCard(UsageBreakdown breakdown, AppPageColors pal) {
    final deviceShare = breakdown.deviceTotalBytes > 0
        ? breakdown.appTotalBytes / breakdown.deviceTotalBytes
        : null;

    return _card(
      pal,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [pal.surfaceAccent, pal.surface, pal.surface],
        stops: const [0, .45, 1],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL DARI APLIKASI',
            style: TextStyle(color: pal.muted, fontSize: 9, letterSpacing: .6),
          ),
          const SizedBox(height: 4),
          Text(
            breakdown.manualMode
                ? '—'
                : formatUsageBytes(breakdown.appTotalBytes),
            style: TextStyle(
              color: pal.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(
                pal,
                breakdown.hasApps
                    ? '${breakdown.apps.length} aplikasi'
                    : 'Belum ada rincian',
              ),
              if (deviceShare != null)
                _pill(pal, '${(deviceShare * 100).round()}% dari perangkat'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Periode: ${formatDate(breakdown.day)} (hari ini)',
            style: TextStyle(color: pal.muted, fontSize: 10),
          ),
          if (breakdown.lastUpdatedAt != null)
            Text(
              'Diperbarui ${_clock(breakdown.lastUpdatedAt!)}',
              style: TextStyle(color: pal.muted, fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(UsageBreakdown breakdown, AppPageColors pal) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Pemakaian per aplikasi',
            style: TextStyle(
              color: pal.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          'Terbesar ke terkecil',
          style: TextStyle(color: pal.muted, fontSize: 9.5),
        ),
      ],
    );
  }

  Widget _appCard(
    AppUsageItem app,
    UsageBreakdownProvider provider,
    AppPageColors pal,
  ) {
    return _card(
      pal,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _appIcon(provider.iconFor(app.appPackageName), pal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        app.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatUsageBytes(app.totalBytes),
                      style: TextStyle(
                        color: pal.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  app.appPackageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.muted, fontSize: 9),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: pal.line)),
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: app.share.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(20),
                                ),
                                gradient: LinearGradient(
                                  colors: [pal.barBright, pal.primaryDeep],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_shareLabel(app.share)} dari pemakaian aplikasi',
                  style: TextStyle(color: pal.muted, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ikon launcher asli dari perangkat. Bila tidak tersedia (paket tidak
  /// terlihat karena batas package visibility, atau platform tanpa channel
  /// Android), dipakai ikon fallback DATAWISE.
  Widget _appIcon(Uint8List? icon, AppPageColors pal) {
    final fallback = Icon(Icons.apps_rounded, color: pal.primary, size: 20);

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: pal.surfaceAlt,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: pal.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: icon == null
          ? fallback
          : Image.memory(
              icon,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
    );
  }

  Widget _qualityCard(UsageBreakdown breakdown, AppPageColors pal) {
    final difference = breakdown.differenceBytes ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.mint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pemakaian aplikasi: '
                  '${formatUsageBytes(breakdown.appTotalBytes)}',
                  style: TextStyle(color: pal.ink, fontSize: 10),
                ),
              ),
              Text(
                'Perangkat: ${formatUsageBytes(breakdown.deviceTotalBytes)}',
                style: TextStyle(color: pal.muted, fontSize: 10),
              ),
            ],
          ),
          if (difference != 0) ...[
            const SizedBox(height: 4),
            Text(
              difference > 0
                  ? 'Selisih ${formatUsageBytes(difference)} belum terpetakan '
                        'ke aplikasi. Ini informasi kualitas data, bukan kuota '
                        'tambahan.'
                  : 'Jumlah aplikasi melebihi agregat perangkat sebesar '
                        '${formatUsageBytes(-difference)}. Angka tetap estimasi.',
              style: TextStyle(color: pal.muted, fontSize: 9, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _permissionCard(AppPageColors pal) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.noticeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.noticeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: pal.warning, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Izin Usage Access belum diberikan',
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'DATAWISE perlu izin akses penggunaan untuk membaca pemakaian '
            'data tiap aplikasi dari statistik Android.',
            style: TextStyle(color: pal.muted, fontSize: 10, height: 1.35),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _openUsageAccessSettings,
              child: const Text('Beri Izin Usage Access'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeCard(
    AppPageColors pal, {
    required IconData icon,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.noticeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.noticeBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: pal.warning, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: pal.ink, fontSize: 10, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(AppPageColors pal) {
    return _card(
      pal,
      child: Column(
        children: [
          Icon(Icons.apps_rounded, color: pal.muted, size: 34),
          const SizedBox(height: 8),
          Text(
            'Belum ada catatan per aplikasi hari ini',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: pal.ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Data muncul setelah sinkronisasi statistik Android mencatat '
            'pemakaian data seluler hari ini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.muted, fontSize: 10, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _pill(AppPageColors pal, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: pal.mint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: pal.primary,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Kartu dengan gaya yang sama seperti kartu Dashboard.
  Widget _card(
    AppPageColors pal, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    Gradient? gradient,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? pal.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        border: pal.isDark ? Border.all(color: pal.line) : null,
        boxShadow: pal.isDark
            ? null
            : [
                BoxShadow(
                  color: pal.primary.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: child,
    );
  }
}
