import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_format.dart';
import 'package_provider.dart';
import 'package_theme.dart';

class PackageDetailPage extends StatefulWidget {
  const PackageDetailPage({super.key});

  @override
  State<PackageDetailPage> createState() => _PackageDetailPageState();
}

class _PackageDetailPageState extends State<PackageDetailPage> {
  String? _packageId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_packageId != null) return;
    final argument = ModalRoute.of(context)?.settings.arguments;
    if (argument is String) _packageId = argument;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editPackage(DataPackage package) async {
    await Navigator.pushNamed(context, Routes.packageForm, arguments: package);
  }

  Future<void> _setActive(DataPackage package) async {
    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || package.id == null) return;

    final provider = context.read<PackageProvider>();
    provider.clearError();

    final ok = await provider.setActive(userId, package.id!);
    if (!mounted) return;

    _snack(
      ok
          ? 'Paket utama berhasil diubah.'
          : provider.errorMessage ?? 'Gagal mengaktifkan paket.',
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PkgColors.primary),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _archivePackage(DataPackage package) async {
    final confirmed = await _confirm(
      title: 'Arsipkan Paket?',
      message:
          'Paket "${package.packageName}" akan dipindahkan ke arsip. '
          'Kategori, catatan penggunaan, aturan, dan riwayat notifikasi '
          'tetap disimpan.',
      confirmLabel: 'Arsipkan',
    );
    if (!confirmed || !mounted) return;

    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || package.id == null) return;

    final provider = context.read<PackageProvider>();
    provider.clearError();

    final success = await provider.archivePackage(package.id!, userId);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
    } else {
      _snack(provider.errorMessage ?? 'Gagal mengarsipkan paket.');
    }
  }

  Future<void> _deletePackage(DataPackage package) async {
    final provider = context.read<PackageProvider>();

    final hasUsage = await provider.hasUsageHistory(package.id!);
    if (!mounted) return;

    // Aturan kontrak data: paket dengan riwayat pemakaian tidak boleh dihapus.
    if (hasUsage) {
      final archive = await _confirm(
        title: 'Paket Tidak Dapat Dihapus',
        message:
            'Paket "${package.packageName}" sudah memiliki riwayat '
            'pemakaian sehingga tidak boleh dihapus. '
            'Anda dapat mengarsipkannya agar tidak muncul di daftar aktif.',
        confirmLabel: 'Arsipkan',
      );
      if (archive && mounted && !package.isArchived) {
        await _archivePackage(package);
      }
      return;
    }

    final confirmed = await _confirm(
      title: 'Hapus Paket?',
      message:
          'Paket "${package.packageName}" akan dihapus permanen. '
          'Tindakan ini tidak dapat dibatalkan.',
      confirmLabel: 'Hapus Permanen',
    );
    if (!confirmed || !mounted) return;

    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || package.id == null) return;

    provider.clearError();
    final success = await provider.deletePackage(package.id!, userId);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
    } else {
      _snack(provider.errorMessage ?? 'Gagal menghapus paket.');
    }
  }

  /// Label selalu di kiri, nilai selalu rata kanan dalam satu baris.
  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: PkgColors.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(color: PkgColors.muted, fontSize: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: PkgColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color bg = PkgColors.chip,
    Color fg = PkgColors.primary,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PackageProvider>(
      builder: (context, provider, child) {
        final package = provider.findById(_packageId);

        if (package == null) {
          return Scaffold(
            backgroundColor: PkgColors.bg,
            appBar: const PkgAppBar(title: 'Detail Paket'),
            body: Center(
              child: Text(
                provider.isLoading
                    ? 'Memuat data paket...'
                    : 'Paket tidak ditemukan.',
              ),
            ),
          );
        }

        final expired = package.isExpiredAt();
        final archived = package.isArchived;
        final isActive = package.status == PackageStatus.active && !expired;
        final canActivate = !isActive && !expired && !archived;
        final frac = timeLeftFraction(package);
        final pct = (frac * 100).round();
        final (value, unit) = splitBytes(package.advertisedTotalQuotaBytes);

        return Scaffold(
          backgroundColor: PkgColors.bg,
          appBar: const PkgAppBar(title: 'Detail Paket'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: PkgColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'INFORMASI PAKET',
                      style: TextStyle(
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: PkgColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit informasi paket',
                    onPressed: provider.isLoading
                        ? null
                        : () => _editPackage(package),
                    icon: const Icon(
                      Icons.edit_note,
                      color: PkgColors.text,
                      size: 26,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: PkgColors.text),
                    onSelected: (v) {
                      if (v == 'archive') _archivePackage(package);
                      if (v == 'delete') _deletePackage(package);
                    },
                    itemBuilder: (_) => [
                      if (!archived)
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Arsipkan Paket'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Hapus Paket'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Kartu utama
              PkgCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PkgStatusPill(package),
                        const Spacer(),
                        if ((package.operatorName ?? '').isNotEmpty)
                          Flexible(
                            child: PkgPill(
                              package.operatorName!,
                              bg: PkgColors.field,
                              icon: Icons.sim_card_outlined,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      package.packageName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: PkgColors.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: PkgColors.field,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TOTAL KUOTA',
                                  style: TextStyle(
                                    letterSpacing: 1,
                                    color: PkgColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        value,
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w800,
                                          color: PkgColors.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      unit,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: PkgColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.pie_chart_outline,
                                      size: 16,
                                      color: PkgColors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Sisa waktu $pct%',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: PkgColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 72,
                            height: 72,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox.expand(
                                  child: CircularProgressIndicator(
                                    value: frac,
                                    strokeWidth: 8,
                                    backgroundColor: PkgColors.chip,
                                    color: PkgColors.primary,
                                  ),
                                ),
                                Text(
                                  '$pct%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: PkgColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.event_available,
                          size: 20,
                          color: PkgColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                color: PkgColors.text,
                                fontSize: 13,
                              ),
                              children: [
                                const TextSpan(text: 'Berakhir '),
                                TextSpan(
                                  text: formatDate(package.endDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (!expired && !archived)
                                  TextSpan(
                                    text:
                                        ' (${package.daysRemaining()} hari lagi)',
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Rincian paket
              PkgCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.donut_large, color: PkgColors.primary),
                        SizedBox(width: 10),
                        Text(
                          'Rincian Paket',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: PkgColors.text,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _infoRow(
                      Icons.data_usage,
                      'Total Kuota',
                      formatBytes(package.advertisedTotalQuotaBytes),
                    ),
                    const Divider(height: 1, color: PkgColors.chip),
                    _infoRow(
                      Icons.calendar_month,
                      'Tanggal Mulai',
                      formatDate(package.startDate),
                    ),
                    const Divider(height: 1, color: PkgColors.chip),
                    _infoRow(
                      Icons.event_available,
                      'Tanggal Berakhir',
                      formatDate(package.endDate),
                    ),
                    const Divider(height: 1, color: PkgColors.chip),
                    _infoRow(
                      Icons.verified_outlined,
                      'Status',
                      PkgStatusPill.labelOf(package),
                    ),
                    const Divider(height: 1, color: PkgColors.chip),
                    _infoRow(Icons.show_chart, 'Pemakaian', 'Belum tersedia'),
                    const Divider(height: 1, color: PkgColors.chip),
                    _infoRow(
                      Icons.pie_chart_outline,
                      'Sisa Kuota',
                      'Belum tersedia',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (canActivate) ...[
                _wideButton(
                  icon: Icons.check_circle_outline,
                  label: 'Jadikan Paket Utama',
                  bg: PkgColors.primary,
                  fg: Colors.white,
                  onTap: provider.isLoading ? null : () => _setActive(package),
                ),
                const SizedBox(height: 10),
              ],
              _wideButton(
                icon: Icons.tune,
                label: 'Edit Informasi Paket',
                onTap: provider.isLoading ? null : () => _editPackage(package),
              ),
              const SizedBox(height: 10),
              if (!archived) ...[
                _wideButton(
                  icon: Icons.archive_outlined,
                  label: 'Arsipkan Paket',
                  onTap: provider.isLoading
                      ? null
                      : () => _archivePackage(package),
                ),
                const SizedBox(height: 10),
              ],
              _wideButton(
                icon: Icons.delete_outline,
                label: 'Hapus Paket',
                bg: Colors.white,
                fg: PkgColors.danger,
                onTap: provider.isLoading
                    ? null
                    : () => _deletePackage(package),
              ),
            ],
          ),
        );
      },
    );
  }
}
