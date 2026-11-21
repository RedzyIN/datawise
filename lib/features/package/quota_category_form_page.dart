import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import 'package_format.dart';
import 'package_theme.dart';
import 'quota_category_format.dart';
import 'quota_category_provider.dart';

/// Argumen route form kategori kuota.
class QuotaCategoryFormArgs {
  const QuotaCategoryFormArgs({required this.package, this.category});

  final DataPackage package;
  final QuotaCategory? category;
}

enum _Unit { gb, mb }

class QuotaCategoryFormPage extends StatefulWidget {
  const QuotaCategoryFormPage({super.key});

  @override
  State<QuotaCategoryFormPage> createState() => _QuotaCategoryFormPageState();
}

class _QuotaCategoryFormPageState extends State<QuotaCategoryFormPage> {
  static const _types = [
    QuotaCategoryType.night,
    QuotaCategoryType.social,
    QuotaCategoryType.appSpecific,
    QuotaCategoryType.custom,
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController();

  QuotaCategory? _editing;
  String? _packageId;
  bool _initialized = false;

  QuotaCategoryType _type = QuotaCategoryType.custom;
  bool _isEnabled = true;
  bool _limitValidity = true;
  _Unit _unit = _Unit.gb;

  DateTime _validFrom = DateUtils.dateOnly(DateTime.now());
  late DateTime _validUntil = _validFrom.add(const Duration(days: 30));

  bool get _isEditing => _editing != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as QuotaCategoryFormArgs?;
    _editing = args?.category;
    _packageId = args?.package.id;

    final package = args?.package;
    final startDate = package == null
        ? DateUtils.dateOnly(DateTime.now())
        : DateUtils.dateOnly(package.startDate);
    final endDate = package == null
        ? startDate.add(const Duration(days: 30))
        : DateUtils.dateOnly(package.endDate);

    _validFrom = startDate;
    _validUntil = endDate.isBefore(startDate) ? startDate : endDate;

    if (_editing != null) {
      final category = _editing!;
      _type = category.categoryType;
      _isEnabled = category.isEnabled;
      _nameController.text = category.categoryName;

      final bytes = category.capacityBytes;
      if (bytes >= 1000000000) {
        _unit = _Unit.gb;
        _capacityController.text = _trim(bytes / 1000000000);
      } else {
        _unit = _Unit.mb;
        _capacityController.text = _trim(bytes / 1000000);
      }

      _limitValidity =
          category.validFrom != null || category.validUntil != null;
      if (category.validFrom != null) {
        _validFrom = DateUtils.dateOnly(category.validFrom!);
      }
      if (category.validUntil != null) {
        _validUntil = DateUtils.dateOnly(category.validUntil!);
      }
    }

    final packageId = _packageId;
    if (packageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<QuotaCategoryProvider>().load(packageId);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  String _trim(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return text;
  }

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  int _toBytes(double value, _Unit unit) =>
      (value * (unit == _Unit.gb ? 1000000000 : 1000000)).round();

  /// Kapasitas yang masih bisa dipakai: sisa kuota utama ditambah kapasitas
  /// kategori ini sendiri ketika sedang diubah.
  int? _availableBytes(QuotaCategoryProvider provider) {
    if (provider.mainCategory == null) return null;
    return provider.mainCapacityBytes + (_editing?.capacityBytes ?? 0);
  }

  Future<void> _selectDate({required bool isStart}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart ? _validFrom : _validUntil,
      firstDate: _validFrom.subtract(const Duration(days: 3650)),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;

    setState(() {
      if (isStart) {
        _validFrom = DateUtils.dateOnly(selected);
        if (_validUntil.isBefore(_validFrom)) _validUntil = _validFrom;
      } else {
        _validUntil = DateUtils.dateOnly(selected);
        if (_validUntil.isBefore(_validFrom)) _validUntil = _validFrom;
      }
    });
  }

  String? _validateCapacity(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Kapasitas kategori wajib diisi.';
    }

    final number = _parse(value);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Kapasitas harus berupa angka lebih dari 0.';
    }

    final bytes = _toBytes(number, _unit);
    final available = _availableBytes(context.read<QuotaCategoryProvider>());

    // Sisakan kuota utama: total kategori tidak boleh melebihi total paket.
    if (available != null && bytes >= available) {
      return 'Kapasitas harus lebih kecil dari ${formatBytes(available)}.';
    }

    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final packageId = _packageId;
    if (packageId == null || packageId.isEmpty) {
      _snack('Paket tidak ditemukan.');
      return;
    }

    final provider = context.read<QuotaCategoryProvider>();
    provider.clearError();

    final category = QuotaCategory(
      id: _editing?.id,
      packageId: packageId,
      categoryName: _nameController.text.trim(),
      categoryType: _type,
      capacityBytes: _toBytes(_parse(_capacityController.text)!, _unit),
      validFrom: _limitValidity ? _validFrom : null,
      validUntil: _limitValidity ? _validUntil : null,
      isEnabled: _isEnabled,
      createdAt: _editing?.createdAt ?? DateTime.now(),
    );

    final success = _isEditing
        ? await provider.update(category)
        : await provider.add(category);

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
    } else {
      _snack(provider.errorMessage ?? 'Gagal menyimpan kategori kuota.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectType(QuotaCategoryType type) {
    final previousDefault = quotaCategoryTypeLabel(_type);
    final current = _nameController.text.trim();

    setState(() {
      _type = type;
      if (current.isEmpty || current == previousDefault) {
        _nameController.text = quotaCategoryTypeLabel(type);
      }
    });
  }

  // ---------- Widget bantu ----------

  InputDecoration _fieldDecoration({String? hint, String? suffix}) {
    OutlineInputBorder border(Color? color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: color == null
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      suffixText: suffix,
      suffixStyle: const TextStyle(color: PkgColors.muted, fontSize: 12),
      filled: true,
      fillColor: PkgColors.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border(null),
      enabledBorder: border(null),
      focusedBorder: border(PkgColors.primary, 1.5),
      errorBorder: border(PkgColors.danger),
      focusedErrorBorder: border(PkgColors.danger, 1.5),
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
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: PkgColors.text,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(color: PkgColors.muted, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _unitToggle(_Unit value, ValueChanged<_Unit> onChanged) {
    Widget seg(_Unit unit, String label) {
      final selected = value == unit;

      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(unit),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: selected ? PkgColors.primary : PkgColors.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 92,
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PkgColors.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [seg(_Unit.gb, 'GB'), seg(_Unit.mb, 'MB')]),
    );
  }

  Widget _typeTile(QuotaCategoryType type) {
    final selected = _type == type;
    final locked = _isEditing;

    return GestureDetector(
      onTap: locked ? null : () => _selectType(type),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? PkgColors.accent : PkgColors.field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              quotaCategoryTypeIcon(type),
              color: locked && !selected ? PkgColors.muted : PkgColors.text,
              size: 18,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                quotaCategoryTypeLabel(type),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: locked && !selected ? PkgColors.muted : PkgColors.text,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_outline,
                color: PkgColors.text,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  Widget _dateRow({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PkgColors.field,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, color: PkgColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: PkgColors.muted, fontSize: 12),
                ),
                Text(
                  formatDate(date),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: PkgColors.text,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: PkgColors.chip,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_calendar,
                color: PkgColors.primary,
                size: 18,
              ),
            ),
          ),
        ],
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PkgColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: PkgColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: PkgColors.primary,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: PkgColors.chip,
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<QuotaCategoryProvider>(
      builder: (context, provider, child) {
        final available = _availableBytes(provider);

        return Scaffold(
          backgroundColor: PkgColors.bg,
          appBar: const PkgAppBar(title: 'Kategori Kuota'),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditing
                            ? 'Ubah Kategori Kuota'
                            : 'Tambah Kategori Kuota',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: PkgColors.text,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: PkgColors.dangerBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Batal',
                          style: TextStyle(
                            color: PkgColors.danger,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Kartu 1: nama dan jenis kategori
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Nama Kategori', trailing: 'Wajib diisi'),
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(
                          fontSize: 16,
                          color: PkgColors.text,
                        ),
                        decoration: _fieldDecoration(
                          hint: 'Contoh: Kuota Malam',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nama kategori wajib diisi.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _label(
                        'Jenis Kategori',
                        trailing: _isEditing ? 'Tidak dapat diubah' : null,
                      ),
                      Row(
                        children: [
                          Expanded(child: _typeTile(_types[0])),
                          const SizedBox(width: 8),
                          Expanded(child: _typeTile(_types[1])),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _typeTile(_types[2])),
                          const SizedBox(width: 8),
                          Expanded(child: _typeTile(_types[3])),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Kartu 2: kapasitas dan masa berlaku
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Kapasitas Kategori'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _capacityController,
                              style: const TextStyle(
                                fontSize: 18,
                                color: PkgColors.text,
                              ),
                              decoration: _fieldDecoration(
                                hint: '5',
                                suffix: 'Besaran',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9,.]'),
                                ),
                              ],
                              validator: _validateCapacity,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _unitToggle(
                            _unit,
                            (unit) => setState(() => _unit = unit),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        available == null
                            ? 'Kapasitas diambil dari kuota utama paket.'
                            : 'Sisa kuota utama yang dapat dialokasikan: '
                                  '${formatBytes(available)}.',
                        style: const TextStyle(
                          color: PkgColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _switchRow(
                        icon: Icons.date_range_outlined,
                        title: 'Batasi Masa Berlaku',
                        subtitle: _limitValidity
                            ? 'Kategori hanya dihitung pada rentang tanggal ini.'
                            : 'Kategori berlaku mengikuti masa aktif paket.',
                        value: _limitValidity,
                        onChanged: (v) => setState(() => _limitValidity = v),
                      ),
                      if (_limitValidity) ...[
                        const SizedBox(height: 12),
                        _dateRow(
                          label: 'Berlaku Mulai',
                          date: _validFrom,
                          onTap: () => _selectDate(isStart: true),
                        ),
                        const SizedBox(height: 8),
                        _dateRow(
                          label: 'Berlaku Sampai',
                          date: _validUntil,
                          onTap: () => _selectDate(isStart: false),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                PkgCard(
                  child: _switchRow(
                    icon: Icons.toggle_on_outlined,
                    title: 'Aktifkan Kategori',
                    subtitle:
                        'Kategori nonaktif tidak dipakai untuk alokasi '
                        'penggunaan.',
                    value: _isEnabled,
                    onChanged: (v) => setState(() => _isEnabled = v),
                  ),
                ),
                const SizedBox(height: 22),

                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: PkgColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: provider.isLoading ? null : _save,
                    icon: provider.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                      _isEditing ? 'Simpan Perubahan' : 'Simpan Kategori',
                    ),
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
