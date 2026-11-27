import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import 'classification_rule_format.dart';
import 'classification_rule_form_page.dart';
import 'classification_rule_provider.dart';
import 'package_theme.dart';
import 'quota_category_provider.dart';

/// Daftar aturan klasifikasi aplikasi milik satu paket.
///
/// Aturan disimpan lewat [ClassificationRuleProvider] yang memakai
/// ClassificationRuleRepository yang sudah tersedia.
class ClassificationRulesPage extends StatefulWidget {
  const ClassificationRulesPage({super.key, required this.package});

  final DataPackage package;

  @override
  State<ClassificationRulesPage> createState() =>
      _ClassificationRulesPageState();
}

class _ClassificationRulesPageState extends State<ClassificationRulesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final packageId = widget.package.id;
    if (packageId == null) return;

    await context.read<QuotaCategoryProvider>().load(packageId);
    if (!mounted) return;

    await context.read<ClassificationRuleProvider>().load(packageId);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openForm({ClassificationRule? rule}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ClassificationRuleFormPage(package: widget.package, rule: rule),
      ),
    );

    if (mounted) await _load();
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

  Future<void> _delete(ClassificationRule rule) async {
    final confirmed = await _confirm(
      title: 'Hapus Aturan?',
      message:
          'Aturan "${rule.ruleName}" akan dihapus. Pemakaian aplikasi yang '
          'tidak lagi cocok dengan aturan lain akan masuk ke kategori utama.',
      confirmLabel: 'Hapus',
    );
    if (!confirmed || !mounted) return;

    final provider = context.read<ClassificationRuleProvider>();
    provider.clearError();

    final success = await provider.delete(rule.id!);
    if (!mounted) return;

    _snack(
      success
          ? 'Aturan dihapus.'
          : provider.errorMessage ?? 'Gagal menghapus aturan.',
    );
  }

  Future<void> _toggle(ClassificationRule rule) async {
    final provider = context.read<ClassificationRuleProvider>();
    provider.clearError();

    final success = await provider.setEnabled(rule, !rule.isEnabled);
    if (!mounted) return;

    _snack(
      success
          ? (rule.isEnabled ? 'Aturan dinonaktifkan.' : 'Aturan diaktifkan.')
          : provider.errorMessage ?? 'Gagal mengubah status aturan.',
    );
  }

  String _categoryName(List<QuotaCategory> categories, String categoryId) {
    for (final category in categories) {
      if (category.id == categoryId) return category.categoryName;
    }
    return 'Kategori tidak ditemukan';
  }

  Widget _ruleCard(ClassificationRule rule, List<QuotaCategory> categories) {
    final pal = PkgPalette.of(context);
    final categoryName = _categoryName(categories, rule.quotaCategoryId);

    return PkgCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PkgIconBox(
                rule.isEnabled ? Icons.rule : Icons.rule_folder_outlined,
                size: 38,
                bg: rule.isEnabled ? pal.accent : pal.chip,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.ruleName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: pal.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ke kategori $categoryName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: pal.muted, size: 20),
                onSelected: (value) {
                  if (value == 'edit') _openForm(rule: rule);
                  if (value == 'toggle') _toggle(rule);
                  if (value == 'delete') _delete(rule);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Ubah Aturan'),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(rule.isEnabled ? 'Nonaktifkan' : 'Aktifkan'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Hapus Aturan'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PkgPill(
                classificationRuleAppLabel(rule.appPackageName),
                icon: Icons.apps,
                bg: pal.field,
              ),
              PkgPill(
                classificationRuleTimeLabel(rule.startMinute, rule.endMinute),
                icon: Icons.schedule,
                bg: pal.field,
              ),
              PkgPill(
                classificationRuleDayLabel(rule.daysOfWeekMask),
                icon: Icons.event_outlined,
                bg: pal.field,
              ),
              PkgPill('Prioritas ${rule.priority}', bg: pal.field),
              if (!rule.isEnabled)
                PkgPill('Nonaktif', bg: pal.dangerBg, fg: pal.danger),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(
    ClassificationRuleProvider provider,
    QuotaCategoryProvider categories,
  ) {
    final pal = PkgPalette.of(context);

    if (provider.isLoading && provider.rules.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                provider.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.danger),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'Aturan klasifikasi menentukan kategori kuota untuk pemakaian tiap '
          'aplikasi. Aturan dengan prioritas lebih besar dipakai lebih dulu, '
          'dan aturan khusus aplikasi mengalahkan aturan semua aplikasi. '
          'Pemakaian yang tidak cocok dengan aturan apa pun masuk ke kategori '
          'utama.',
          style: TextStyle(color: pal.muted, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 14),
        if (provider.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              provider.errorMessage!,
              style: TextStyle(color: pal.danger, fontSize: 12),
            ),
          ),
        if (categories.categories.isEmpty)
          PkgCard(
            child: Text(
              'Paket ini belum memiliki kategori kuota. Tambahkan kategori '
              'lebih dahulu sebelum membuat aturan klasifikasi.',
              style: TextStyle(color: pal.muted, fontSize: 12),
            ),
          )
        else if (provider.rules.isEmpty)
          PkgCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.rule_folder_outlined, color: pal.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Belum ada aturan klasifikasi',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: pal.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Seluruh pemakaian aplikasi saat ini masuk ke kategori '
                  'utama. Tambahkan aturan untuk memisahkan kuota aplikasi '
                  'atau kuota malam.',
                  style: TextStyle(
                    color: pal.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          )
        else
          for (final rule in provider.rules)
            _ruleCard(rule, categories.categories),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: pal.primary,
              foregroundColor: pal.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: provider.isLoading || categories.categories.isEmpty
                ? null
                : () => _openForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text(
              'Tambah Aturan',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PkgPalette.of(context).bg,
      appBar: const PkgAppBar(title: 'Aturan Klasifikasi'),
      body: Consumer2<ClassificationRuleProvider, QuotaCategoryProvider>(
        builder: (context, provider, categories, child) =>
            _body(provider, categories),
      ),
    );
  }
}
