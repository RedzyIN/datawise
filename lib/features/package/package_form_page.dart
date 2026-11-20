import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_format.dart';
import 'package_provider.dart';
import 'package_theme.dart';

enum _Unit { gb, mb }

class PackageFormPage extends StatefulWidget {
  const PackageFormPage({super.key});

  @override
  State<PackageFormPage> createState() => _PackageFormPageState();
}

class _PackageFormPageState extends State<PackageFormPage> {
  static const _baseOperators = [
    'Telkomsel',
    'Indosat',
    'XL',
    'Tri',
    'Smartfren',
  ];
  static const _presetDays = [1, 7, 30];
  static const _categories = [
    ('Utama', Icons.public),
    ('Malam', Icons.nightlight_outlined),
    ('Sosmed', Icons.devices_other),
    ('Add-on', Icons.extension_outlined),
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _totalQuotaController = TextEditingController();
  final _usedQuotaController = TextEditingController();

  DataPackage? _editing;
  bool _initialized = false;
  bool _isActive = false;

  String? _operator;
  int _category = 0; // Hanya tampilan; belum disimpan ke database.
  bool _criticalReminder = true; // Hanya tampilan; belum disimpan.

  _Unit _totalUnit = _Unit.gb;
  _Unit _usedUnit = _Unit.gb;

  /// null = kustom (tanggal berakhir dipilih manual).
  int? _validityDays = 30;

  DateTime _startDate = DateUtils.dateOnly(DateTime.now());
  late DateTime _endDate = _startDate.add(const Duration(days: 30));

  bool get _isEditing => _editing != null;

  List<String> get _operators => [
    ..._baseOperators,
    if (_operator != null && !_baseOperators.contains(_operator)) _operator!,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _editing = ModalRoute.of(context)?.settings.arguments as DataPackage?;

    if (_editing != null) {
      final package = _editing!;
      _nameController.text = package.packageName;
      _operator = (package.operatorName ?? '').isEmpty
          ? null
          : package.operatorName;

      final bytes = package.advertisedTotalQuotaBytes;
      if (bytes >= 1000000000) {
        _totalUnit = _Unit.gb;
        _totalQuotaController.text = _trim(bytes / 1000000000);
      } else {
        _totalUnit = _Unit.mb;
        _totalQuotaController.text = _trim(bytes / 1000000);
      }

      _startDate = DateUtils.dateOnly(package.startDate);
      _endDate = DateUtils.dateOnly(package.endDate);
      final length = _endDate.difference(_startDate).inDays;
      _validityDays = _presetDays.contains(length) ? length : null;
      _isActive = package.status == PackageStatus.active;
    } else {
      _isActive = context.read<PackageProvider>().activePackage == null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalQuotaController.dispose();
    _usedQuotaController.dispose();
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

  Future<void> _selectStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;

    setState(() {
      _startDate = DateUtils.dateOnly(selected);
      if (_validityDays != null) {
        _endDate = _startDate.add(Duration(days: _validityDays!));
      } else if (_endDate.isBefore(_startDate)) {
        _endDate = _startDate;
      }
    });
  }

  Future<void> _selectEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() => _endDate = DateUtils.dateOnly(selected));
  }

  String? _validateTotal(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Total kuota wajib diisi.';
    }
    final number = _parse(value);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Total kuota harus berupa angka lebih dari 0.';
    }
    return null;
  }

  String? _validateUsed(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final used = _parse(value);
    if (used == null || !used.isFinite || used < 0) {
      return 'Kuota terpakai harus berupa angka 0 atau lebih.';
    }
    final total = _parse(_totalQuotaController.text);
    if (total != null && total > 0) {
      if (_toBytes(used, _usedUnit) > _toBytes(total, _totalUnit)) {
        return 'Kuota terpakai tidak boleh melebihi total kuota.';
      }
    }
    return null;
  }

  Future<void> _savePackage() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengguna belum terautentikasi.')),
      );
      return;
    }

    final totalBytes = _toBytes(
      _parse(_totalQuotaController.text)!,
      _totalUnit,
    );
    final usedValue = _parse(_usedQuotaController.text);
    final usedBytes = (usedValue == null || usedValue <= 0)
        ? 0
        : _toBytes(usedValue, _usedUnit);

    final now = DateTime.now();
    final endPassed = _endDate.isBefore(DateUtils.dateOnly(now));

    final PackageStatus status;
    if (_editing?.status == PackageStatus.archived) {
      status = PackageStatus.archived;
    } else if (endPassed) {
      status = PackageStatus.expired;
    } else if (_isActive) {
      status = PackageStatus.active;
    } else {
      status = PackageStatus.inactive;
    }

    final package = DataPackage(
      id: _editing?.id,
      userId: userId,
      packageName: _nameController.text.trim(),
      operatorName: _operator,
      advertisedTotalQuotaBytes: totalBytes,
      startDate: _startDate,
      endDate: _endDate,
      status: status,
      createdAt: _editing?.createdAt ?? now,
      updatedAt: now,
    );

    final provider = context.read<PackageProvider>();
    final success = _isEditing
        ? await provider.updatePackage(package)
        : await provider.addPackage(package, initialUsedBytes: usedBytes);

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Gagal menyimpan paket.'),
        ),
      );
    }
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
    Widget seg(_Unit u, String label) {
      final selected = value == u;

      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(u),
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

  Widget _quotaRow({
    required TextEditingController controller,
    required String hint,
    required String? Function(String?) validator,
    required _Unit unit,
    required ValueChanged<_Unit> onUnit,
    bool showSuffix = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            style: const TextStyle(fontSize: 18, color: PkgColors.text),
            decoration: _fieldDecoration(
              hint: hint,
              suffix: showSuffix ? 'Besaran' : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            validator: validator,
          ),
        ),
        const SizedBox(width: 8),
        _unitToggle(unit, onUnit),
      ],
    );
  }

  Widget _selectChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? PkgColors.primary : PkgColors.field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: PkgColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? Colors.white : PkgColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryTile(int index) {
    final (label, icon) = _categories[index];
    final selected = _category == index;

    return GestureDetector(
      onTap: () => setState(() => _category = index),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? PkgColors.accent : PkgColors.field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: PkgColors.text, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: PkgColors.text,
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

  Widget _validityChip(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? PkgColors.primary : PkgColors.field,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: selected ? Colors.white : PkgColors.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateBox() {
    final custom = _validityDays == null;

    Widget dateBlock(String label, DateTime date, {bool bold = false}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: PkgColors.muted, fontSize: 12),
          ),
          Text(
            formatDate(date),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: bold ? PkgColors.primary : PkgColors.text,
            ),
          ),
        ],
      );
    }

    Widget roundBtn(VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: PkgColors.chip,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.edit_calendar,
            color: PkgColors.primary,
            size: 20,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PkgColors.field,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month,
                color: PkgColors.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(child: dateBlock('Tanggal Mulai', _startDate)),
              roundBtn(_selectStartDate),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _dot(),
                const Expanded(child: Divider(color: PkgColors.chip)),
                const Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: PkgColors.primary,
                ),
                const Expanded(child: Divider(color: PkgColors.chip)),
                _dot(),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(
                Icons.event_available,
                color: PkgColors.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: dateBlock(
                  custom ? 'Tanggal Berakhir' : 'Berakhir Otomatis',
                  _endDate,
                  bold: true,
                ),
              ),
              if (custom)
                roundBtn(_selectEndDate)
              else
                const PkgPill('Auto-sync'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot() => Container(
    width: 8,
    height: 8,
    decoration: const BoxDecoration(
      color: PkgColors.primary,
      shape: BoxShape.circle,
    ),
  );

  Widget _switchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return PkgCard(
      padding: const EdgeInsets.all(14),
      child: Row(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final archived = _editing?.status == PackageStatus.archived;
    final endPassed = _endDate.isBefore(DateUtils.dateOnly(DateTime.now()));

    return Consumer<PackageProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: PkgColors.bg,
          appBar: const PkgAppBar(title: 'Paket Kuota'),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditing ? 'Ubah Paket Kuota' : 'Tambah Paket Kuota',
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

                // Kartu 1: nama, operator, kategori
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Nama Paket', trailing: 'Wajib diisi'),
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(
                          fontSize: 16,
                          color: PkgColors.text,
                        ),
                        decoration: _fieldDecoration(
                          hint: 'Contoh: Paket Bulanan 30 GB',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nama paket wajib diisi.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _label('Operator Telekomunikasi'),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final name in _operators) ...[
                              _selectChip(
                                label: name,
                                selected: _operator == name,
                                onTap: () => setState(
                                  () => _operator = _operator == name
                                      ? null
                                      : name,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _label('Kategori Kuota'),
                      Row(
                        children: [
                          Expanded(child: _categoryTile(0)),
                          const SizedBox(width: 8),
                          Expanded(child: _categoryTile(1)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _categoryTile(2)),
                          const SizedBox(width: 8),
                          Expanded(child: _categoryTile(3)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Kartu 2: kuota & masa berlaku
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Jumlah Total Kuota'),
                      _quotaRow(
                        controller: _totalQuotaController,
                        hint: '30',
                        validator: _validateTotal,
                        unit: _totalUnit,
                        onUnit: (u) => setState(() => _totalUnit = u),
                        showSuffix: true,
                      ),
                      if (!_isEditing) ...[
                        const SizedBox(height: 14),
                        _label('Kuota Sudah Terpakai (Opsional)'),
                        _quotaRow(
                          controller: _usedQuotaController,
                          hint: '0',
                          validator: _validateUsed,
                          unit: _usedUnit,
                          onUnit: (u) => setState(() => _usedUnit = u),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _label('Masa Berlaku'),
                      Row(
                        children: [
                          for (final days in _presetDays) ...[
                            _validityChip(
                              '$days Hari',
                              _validityDays == days,
                              () => setState(() {
                                _validityDays = days;
                                _endDate = _startDate.add(Duration(days: days));
                              }),
                            ),
                            const SizedBox(width: 8),
                          ],
                          _validityChip(
                            'Kustom',
                            _validityDays == null,
                            () => setState(() => _validityDays = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _dateBox(),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                _switchCard(
                  icon: Icons.verified_outlined,
                  title: 'Jadikan Paket Utama',
                  subtitle: archived
                      ? 'Paket diarsipkan tidak dapat diaktifkan.'
                      : endPassed
                      ? 'Paket kedaluwarsa tidak dapat diaktifkan.'
                      : 'Hanya satu paket yang bisa menjadi paket utama.',
                  value: _isActive && !archived && !endPassed,
                  onChanged: (archived || endPassed)
                      ? null
                      : (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 14),

                _switchCard(
                  icon: Icons.notifications_active_outlined,
                  title: 'Pengingat Kuota Kritis',
                  subtitle: 'Peringatan otomatis saat sisa data mencapai batas kritis 20%.',
                  value: _criticalReminder,
                  onChanged: (v) => setState(() => _criticalReminder = v),
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
                    onPressed: provider.isLoading ? null : _savePackage,
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
                      _isEditing ? 'Simpan Perubahan' : 'Simpan Paket',
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
