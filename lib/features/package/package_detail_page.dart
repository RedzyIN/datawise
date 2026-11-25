import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_format.dart';
import 'package_provider.dart';
import 'package_theme.dart';
import 'quota_category_form_page.dart';
import 'quota_category_format.dart';
import 'quota_category_provider.dart';

class PackageDetailPage extends StatefulWidget {
  const PackageDetailPage({super.key});

  @override
  State<PackageDetailPage> createState() => _PackageDetailPageState();
}

class _PackageDetailPageState extends State<PackageDetailPage> {
  String? _packageId;
  String? _categoriesLoadedFor;

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

  /// Memuat kategori kuota sekali untuk paket yang sedang dibuka.
  void _ensureCategories(String packageId) {
    if (_categoriesLoadedFor == packageId) return;
    _categoriesLoadedFor = packageId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<QuotaCategoryProvider>().load(packageId);
    });
  }

  Future<void> _openCategoryForm(
    DataPackage package, {
    QuotaCategory? category,
  }) async {
    await Navigator.pushNamed(
      context,
      Routes.quotaCategoryForm,
      arguments: QuotaCategoryFormArgs(package: package, category: category),
    );
  }

  Future<void> _deleteCategory(QuotaCategory category) async {
    final confirmed = await _confirm(
      title: 'Hapus Kategori?',
      message:
          'Kategori "${category.categoryName}" akan dihapus dan '
          'kapasitasnya dikembalikan ke kuota utama.',
      confirmLabel: 'Hapus',
    );
    if (!confirmed || !mounted) return;

    final provider = context.read<QuotaCategoryProvider>();
    provider.clearError();

    final success = await provider.delete(category.id!);
    if (!mounted) return;

    _snack(
      success
          ? 'Kategori dihapus.'
          : provider.errorMessage ?? 'Gagal menghapus kategori.',
    );
  }

  Future<void> _toggleCategory(QuotaCategory category) async {
    final provider = context.read<QuotaCategoryProvider>();
    provider.clearError();

    final success = await provider.setEnabled(category, !category.isEnabled);
    if (!mounted) return;

    _snack(
      success
          ? (category.isEnabled
                ? 'Kategori dinonaktifkan.'
                : 'Kategori diaktifkan.')
          : provider.errorMessage ?? 'Gagal mengubah status kategori.',
    );
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
            style: FilledButton.styleFrom(
              backgroundColor: PkgPalette.of(context).primary,
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: PkgPalette.of(context).primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(color: PkgPalette.of(context).muted, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: PkgPalette.of(context).text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryRow(DataPackage package, QuotaCategory category) {
    final isMain = category.categoryType == QuotaCategoryType.main;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          PkgIconBox(
            quotaCategoryTypeIcon(category.categoryType),
            size: 38,
            bg: isMain
                ? PkgPalette.of(context).accent
                : PkgPalette.of(context).field,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        category.categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: PkgPalette.of(context).text,
                        ),
                      ),
                    ),
                    if (isMain) ...[
                      const SizedBox(width: 6),
                      PkgPill(
                        'WAJIB',
                        bg: PkgPalette.of(context).primary,
                        fg: PkgPalette.of(context).onPrimary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatBytes(category.capacityBytes)} • '
                  '${quotaCategoryValidityLabel(category)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: PkgPalette.of(context).muted,
                    fontSize: 11,
                  ),
                ),
                if (!category.isEnabled)
                  Text(
                    'Nonaktif',
                    style: TextStyle(
                      color: PkgPalette.of(context).danger,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          if (!isMain)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: PkgPalette.of(context).muted,
                size: 20,
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  _openCategoryForm(package, category: category);
                }
                if (value == 'toggle') _toggleCategory(category);
                if (value == 'delete') _deleteCategory(category);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Ubah Kategori'),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(category.isEnabled ? 'Nonaktifkan' : 'Aktifkan'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Hapus Kategori'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _categorySection(DataPackage package, QuotaCategoryProvider provider) {
    final categories = provider.categories;
    final additional = provider.additionalCategories;

    return PkgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.donut_small, color: PkgPalette.of(context).primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kategori Kuota',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: PkgPalette.of(context).text,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tambah kategori kuota',
                onPressed: provider.isLoading
                    ? null
                    : () => _openCategoryForm(package),
                icon: Icon(
                  Icons.add_circle,
                  color: PkgPalette.of(context).primary,
                  size: 26,
                ),
              ),
            ],
          ),
          Text(
            'Satu paket dapat memiliki beberapa kategori. Kapasitas kategori '
            'tambahan diambil dari kuota utama sehingga total paket tetap sama.',
            style: TextStyle(
              color: PkgPalette.of(context).muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          if (provider.isLoading && categories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Memuat kategori...',
                style: TextStyle(
                  color: PkgPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            )
          else if (categories.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PkgPalette.of(context).field,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Belum ada kategori kuota untuk paket ini.',
                style: TextStyle(
                  color: PkgPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PkgPalette.of(context).field,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TERALOKASI',
                          style: TextStyle(
                            letterSpacing: 1,
                            color: PkgPalette.of(context).muted,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          formatBytes(provider.totalAllocatedBytes),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: PkgPalette.of(context).primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${additional.length} kategori tambahan',
                    style: TextStyle(
                      color: PkgPalette.of(context).muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            for (final category in categories) ...[
              Divider(height: 1, color: PkgPalette.of(context).chip),
              _categoryRow(package, category),
            ],
          ],
        ],
      ),
    );
  }

  Widget _wideButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? bg,
    Color? fg,
  }) {
    final pal = PkgPalette.of(context);

    // Warna default mengikuti warna utama palet aplikasi.
    // Warna khusus tetap bisa diberikan melalui parameter bg dan fg.
    final background = bg ?? pal.primary;
    final foreground = fg ?? pal.onPrimary;

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
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
            backgroundColor: PkgPalette.of(context).bg,
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

        _ensureCategories(package.id!);

        final expired = package.isExpiredAt();
        final archived = package.isArchived;
        final isActive = package.status == PackageStatus.active && !expired;
        final canActivate = !isActive && !expired && !archived;
        final frac = timeLeftFraction(package);
        final pct = (frac * 100).round();
        final (value, unit) = splitBytes(package.advertisedTotalQuotaBytes);

        return Scaffold(
          backgroundColor: PkgPalette.of(context).bg,
          appBar: const PkgAppBar(title: 'Detail Paket'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: PkgPalette.of(context).primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'INFORMASI PAKET',
                      style: TextStyle(
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: PkgPalette.of(context).text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit informasi paket',
                    onPressed: provider.isLoading
                        ? null
                        : () => _editPackage(package),
                    icon: Icon(
                      Icons.edit_note,
                      color: PkgPalette.of(context).text,
                      size: 26,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: PkgPalette.of(context).text,
                    ),
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
                              bg: PkgPalette.of(context).field,
                              icon: Icons.sim_card_outlined,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      package.packageName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: PkgPalette.of(context).text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: PkgPalette.of(context).field,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TOTAL KUOTA',
                                  style: TextStyle(
                                    letterSpacing: 1,
                                    color: PkgPalette.of(context).muted,
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
                                        style: TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                          color: PkgPalette.of(context).primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      unit,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: PkgPalette.of(context).muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.pie_chart_outline,
                                      size: 16,
                                      color: PkgPalette.of(context).primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Sisa waktu $pct%',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: PkgPalette.of(context).primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox.expand(
                                  child: CircularProgressIndicator(
                                    value: frac,
                                    strokeWidth: 6,
                                    backgroundColor: PkgPalette.of(context)
                                        .chip,
                                    color: PkgPalette.of(context).primary,
                                  ),
                                ),
                                Text(
                                  '$pct%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: PkgPalette.of(context).primary,
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
                        Icon(
                          Icons.event_available,
                          size: 20,
                          color: PkgPalette.of(context).primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                color: PkgPalette.of(context).text,
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
                    Row(
                      children: [
                        Icon(
                          Icons.donut_large,
                          color: PkgPalette.of(context).primary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Rincian Paket',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: PkgPalette.of(context).text,
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
                    Divider(height: 1, color: PkgPalette.of(context).chip),
                    _infoRow(
                      Icons.calendar_month,
                      'Tanggal Mulai',
                      formatDate(package.startDate),
                    ),
                    Divider(height: 1, color: PkgPalette.of(context).chip),
                    _infoRow(
                      Icons.event_available,
                      'Tanggal Berakhir',
                      formatDate(package.endDate),
                    ),
                    Divider(height: 1, color: PkgPalette.of(context).chip),
                    _infoRow(
                      Icons.verified_outlined,
                      'Status',
                      PkgStatusPill.labelOf(package),
                    ),
                    Divider(height: 1, color: PkgPalette.of(context).chip),
                    _infoRow(Icons.show_chart, 'Pemakaian', 'Belum tersedia'),
                    Divider(height: 1, color: PkgPalette.of(context).chip),
                    _infoRow(
                      Icons.pie_chart_outline,
                      'Sisa Kuota',
                      'Belum tersedia',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Kategori kuota (Multiple Quota Management)
              Consumer<QuotaCategoryProvider>(
                builder: (context, categories, child) =>
                    _categorySection(package, categories),
              ),
              const SizedBox(height: 14),

              if (canActivate) ...[
                _wideButton(
                  icon: Icons.check_circle_outline,
                  label: 'Jadikan Paket Utama',
                  bg: PkgPalette.of(context).primary,
                  fg: PkgPalette.of(context).onPrimary,
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
                bg: PkgPalette.of(context).card,
                fg: PkgPalette.of(context).danger,
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
