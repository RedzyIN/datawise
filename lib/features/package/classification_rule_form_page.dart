import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import 'classification_rule_format.dart';
import 'classification_rule_provider.dart';
import 'package_theme.dart';
import 'quota_category_provider.dart';

/// Form tambah/ubah aturan klasifikasi. Isi aturan mengikuti field
/// ClassificationRule yang sudah ada; validasi akhir tetap di repository.
class ClassificationRuleFormPage extends StatefulWidget {
  const ClassificationRuleFormPage({
    super.key,
    required this.package,
    this.rule,
  });

  final DataPackage package;
  final ClassificationRule? rule;

  @override
  State<ClassificationRuleFormPage> createState() =>
      _ClassificationRuleFormPageState();
}

class _ClassificationRuleFormPageState
    extends State<ClassificationRuleFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _appController = TextEditingController();
  final _priorityController = TextEditingController();

  String? _categoryId;
  bool _limitTime = false;
  int _startMinute = 0;
  int _endMinute = 1440;
  int _daysMask = 127;
  bool _isEnabled = true;
  bool _isSaving = false;

  bool get _isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();

    final rule = widget.rule;
    if (rule == null) {
      _priorityController.text = '10';
      return;
    }

    _nameController.text = rule.ruleName;
    _appController.text = rule.appPackageName ?? '';
    _priorityController.text = '${rule.priority}';
    _categoryId = rule.quotaCategoryId;
    _limitTime = rule.startMinute != null && rule.endMinute != null;
    _startMinute = rule.startMinute ?? 0;
    _endMinute = rule.endMinute ?? 1440;
    _daysMask = rule.daysOfWeekMask;
    _isEnabled = rule.isEnabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _appController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _startMinute : (_endMinute % 1440);

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;

    final minute = picked.hour * 60 + picked.minute;

    setState(() {
      if (isStart) {
        _startMinute = minute;
        // Jam mulai 00:00 tetap berarti tengah malam, bukan akhir hari.
      } else {
        // TimePicker tidak mengenal 24:00; 00:00 pada jam selesai berarti
        // sampai akhir hari agar aturan 22:00 - 00:00 tetap valid.
        _endMinute = minute == 0 ? 1440 : minute;
      }
    });
  }

  void _toggleDay(int index) {
    setState(() => _daysMask ^= 1 << index);
  }

  Future<void> _save(List<QuotaCategory> categories) async {
    final categoryId =
        _categoryId ?? (categories.isEmpty ? null : categories.first.id);

    if (categoryId == null) {
      _snack('Tambahkan kategori kuota sebelum menyimpan aturan.');
      return;
    }

    if (_daysMask == 0) {
      _snack('Pilih minimal satu hari aktif.');
      return;
    }

    if (_limitTime && _startMinute == _endMinute) {
      _snack('Jam mulai dan jam selesai tidak boleh sama.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final packageId = widget.package.id;
    if (packageId == null) {
      _snack('Paket tidak ditemukan.');
      return;
    }

    final app = _appController.text.trim();

    final rule = ClassificationRule(
      id: widget.rule?.id,
      quotaCategoryId: categoryId,
      ruleName: _nameController.text.trim(),
      appPackageName: app.isEmpty ? null : app,
      startMinute: _limitTime ? _startMinute : null,
      endMinute: _limitTime ? _endMinute : null,
      daysOfWeekMask: _daysMask,
      priority: int.parse(_priorityController.text.trim()),
      isEnabled: _isEnabled,
      createdAt: widget.rule?.createdAt ?? DateTime.now(),
    );

    final provider = context.read<ClassificationRuleProvider>();
    provider.clearError();

    setState(() => _isSaving = true);
    final success = _isEditing
        ? await provider.update(rule)
        : await provider.add(rule);
    if (!mounted) return;

    setState(() => _isSaving = false);

    if (success) {
      Navigator.pop(context, true);
      return;
    }

    _snack(provider.errorMessage ?? 'Gagal menyimpan aturan klasifikasi.');
  }

  // ---------- Widget bantu ----------

  InputDecoration _fieldDecoration({String? hint}) {
    OutlineInputBorder border(Color? color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: color == null
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: PkgPalette.of(context).field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border(null),
      enabledBorder: border(null),
      focusedBorder: border(PkgPalette.of(context).primary, 1.5),
      errorBorder: border(PkgPalette.of(context).danger),
      focusedErrorBorder: border(PkgPalette.of(context).danger, 1.5),
    );
  }

  Widget _label(String text, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: PkgPalette.of(context).text,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(
                color: PkgPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _fieldHint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          color: PkgPalette.of(context).muted,
          fontSize: 12,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        PkgIconBox(icon, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PkgPalette.of(context).text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: PkgPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: PkgPalette.of(context).onPrimary,
          activeTrackColor: PkgPalette.of(context).primary,
          inactiveThumbColor: PkgPalette.of(context).onPrimary,
          inactiveTrackColor: PkgPalette.of(context).chip,
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ],
    );
  }

  Widget _timeRow({
    required String label,
    required int minute,
    required VoidCallback onTap,
  }) {
    final value = classificationRuleClockLabel(minute);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: PkgPalette.of(context).field,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.schedule,
              color: PkgPalette.of(context).primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: PkgPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: PkgPalette.of(context).text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categorySelector(List<QuotaCategory> categories) {
    final selectedId =
        _categoryId ?? (categories.isEmpty ? null : categories.first.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: PkgPalette.of(context).field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: selectedId,
          hint: Text(
            'Pilih kategori tujuan',
            style: TextStyle(color: PkgPalette.of(context).muted, fontSize: 14),
          ),
          items: [
            for (final category in categories)
              DropdownMenuItem(
                value: category.id,
                child: Text(
                  category.categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: PkgPalette.of(context).text,
                  ),
                ),
              ),
          ],
          onChanged: (value) => setState(() => _categoryId = value),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = PkgPalette.of(context);

    return Consumer<QuotaCategoryProvider>(
      builder: (context, categoryProvider, child) {
        final categories = categoryProvider.categories;
        final days = classificationRuleDayLabel(_daysMask);

        return Scaffold(
          backgroundColor: pal.bg,
          appBar: PkgAppBar(
            title: _isEditing ? 'Ubah Aturan' : 'Tambah Aturan',
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                // Kartu 1: nama, aplikasi, kategori tujuan
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Nama Aturan', trailing: 'Wajib diisi'),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(fontSize: 15, color: pal.text),
                        decoration: _fieldDecoration(
                          hint: 'Contoh: WhatsApp Kuota Sosial',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Nama aturan wajib diisi.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _label('Paket Aplikasi', trailing: 'Opsional'),
                      TextFormField(
                        controller: _appController,
                        style: TextStyle(fontSize: 15, color: pal.text),
                        decoration: _fieldDecoration(hint: 'com.whatsapp'),
                        autocorrect: false,
                      ),
                      _fieldHint(
                        'Kosongkan untuk aturan semua aplikasi. Isi nama paket '
                        'Android agar aturan hanya berlaku untuk aplikasi itu.',
                      ),
                      const SizedBox(height: 16),
                      _label('Kategori Tujuan', trailing: 'Wajib dipilih'),
                      _categorySelector(categories),
                      if (categories.isEmpty)
                        _fieldHint(
                          'Paket ini belum memiliki kategori kuota. Tambahkan '
                          'kategori terlebih dahulu.',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Kartu 2: waktu dan hari aktif
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _switchRow(
                        icon: Icons.schedule,
                        title: 'Batasi Jam Penggunaan',
                        subtitle: _limitTime
                            ? 'Aturan hanya berlaku pada rentang jam ini.'
                            : 'Aturan berlaku sepanjang hari.',
                        value: _limitTime,
                        onChanged: (value) =>
                            setState(() => _limitTime = value),
                      ),
                      if (_limitTime) ...[
                        const SizedBox(height: 12),
                        _timeRow(
                          label: 'Jam Mulai',
                          minute: _startMinute,
                          onTap: () => _pickTime(isStart: true),
                        ),
                        const SizedBox(height: 8),
                        _timeRow(
                          label: 'Jam Selesai',
                          minute: _endMinute,
                          onTap: () => _pickTime(isStart: false),
                        ),
                        _fieldHint(
                          'Rentang lintas tengah malam didukung, misalnya '
                          '22:00 - 02:00. Jam selesai 00:00 dibaca sampai '
                          'akhir hari.',
                        ),
                        if (_startMinute == _endMinute)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Jam mulai dan jam selesai tidak boleh sama.',
                              style: TextStyle(color: pal.danger, fontSize: 12),
                            ),
                          ),
                      ],
                      const SizedBox(height: 16),
                      _label('Hari Aktif', trailing: days),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var index = 0; index < 7; index++)
                            FilterChip(
                              label: Text(classificationRuleDayName(index)),
                              selected: (_daysMask & (1 << index)) != 0,
                              onSelected: (_) => _toggleDay(index),
                            ),
                        ],
                      ),
                      if (_daysMask == 0)
                        _fieldHint('Pilih minimal satu hari aktif.'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Kartu 3: prioritas dan status
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Prioritas', trailing: 'Angka 0 atau lebih'),
                      TextFormField(
                        controller: _priorityController,
                        style: TextStyle(fontSize: 15, color: pal.text),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: _fieldDecoration(hint: '10'),
                        validator: (value) {
                          final number = int.tryParse(value?.trim() ?? '');
                          if (number == null) {
                            return 'Prioritas wajib berupa angka.';
                          }
                          return number < 0
                              ? 'Prioritas tidak boleh negatif.'
                              : null;
                        },
                      ),
                      _fieldHint(
                        'Aturan dengan prioritas lebih besar menang ketika '
                        'beberapa aturan cocok dengan pemakaian yang sama.',
                      ),
                      const SizedBox(height: 16),
                      _switchRow(
                        icon: Icons.toggle_on_outlined,
                        title: 'Aturan Aktif',
                        subtitle: _isEnabled
                            ? 'Aturan dipakai saat klasifikasi pemakaian.'
                            : 'Aturan disimpan tetapi tidak dipakai.',
                        value: _isEnabled,
                        onChanged: (value) =>
                            setState(() => _isEnabled = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: pal.primary,
                      foregroundColor: pal.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isSaving || categories.isEmpty
                        ? null
                        : () => _save(categories),
                    child: Text(
                      _isSaving ? 'Menyimpan...' : 'Simpan Aturan',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pal.danger,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.maybePop(context),
                    child: const Text('Batal'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
