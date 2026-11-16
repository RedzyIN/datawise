import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_format.dart';
import 'package_provider.dart';

enum _Unit { gb, mb }

class PackageFormPage extends StatefulWidget {
  const PackageFormPage({super.key});

  @override
  State<PackageFormPage> createState() => _PackageFormPageState();
}

class _PackageFormPageState extends State<PackageFormPage> {
  static const _operators = ['Telkomsel', 'Indosat', 'XL', 'Tri', 'Smartfren'];
  static const _presetDays = [1, 7, 30];

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _operatorController = TextEditingController();
  final _totalQuotaController = TextEditingController();
  final _usedQuotaController = TextEditingController();

  DataPackage? _editing;
  bool _initialized = false;
  bool _isActive = false;

  _Unit _totalUnit = _Unit.gb;
  _Unit _usedUnit = _Unit.gb;

  /// null = kustom (tanggal berakhir dipilih manual).
  int? _validityDays = 30;

  DateTime _startDate = DateUtils.dateOnly(DateTime.now());
  late DateTime _endDate = _startDate.add(const Duration(days: 30));

  bool get _isEditing => _editing != null;

  @override
  void initState() {
    super.initState();
    _operatorController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;
    _initialized = true;

    _editing = ModalRoute.of(context)?.settings.arguments as DataPackage?;

    if (_editing != null) {
      final package = _editing!;

      _nameController.text = package.packageName;
      _operatorController.text = package.operatorName ?? '';

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
    _operatorController.dispose();
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

  void _applyValidity(int days) {
    _validityDays = days;
    _endDate = _startDate.add(Duration(days: days));
  }

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
    final number = _parse(value ?? '');
    if (value == null || value.trim().isEmpty) {
      return 'Total kuota wajib diisi.';
    }
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
    final today = DateUtils.dateOnly(now);
    final endPassed = _endDate.isBefore(today);

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

    final operatorName = _operatorController.text.trim();

    final package = DataPackage(
      id: _editing?.id,
      userId: userId,
      packageName: _nameController.text.trim(),
      operatorName: operatorName.isEmpty ? null : operatorName,
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

  Widget _unitToggle(_Unit value, ValueChanged<_Unit> onChanged) {
    return SegmentedButton<_Unit>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _Unit.gb, label: Text('GB')),
        ButtonSegment(value: _Unit.mb, label: Text('MB')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }

  Widget _quotaRow({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String? Function(String?) validator,
    required _Unit unit,
    required ValueChanged<_Unit> onUnit,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            validator: validator,
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _unitToggle(unit, onUnit),
        ),
      ],
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime date,
    VoidCallback? onTap,
    String? badge,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: const Icon(Icons.calendar_today),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(
        formatDate(date),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      trailing: badge != null
          ? Chip(label: Text(badge), visualDensity: VisualDensity.compact)
          : (onTap != null ? const Icon(Icons.edit_calendar) : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final archived = _editing?.status == PackageStatus.archived;
    final endPassed = _endDate.isBefore(DateUtils.dateOnly(DateTime.now()));

    return Consumer<PackageProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_isEditing ? 'Ubah Paket' : 'Tambah Paket Kuota'),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Paket',
                    hintText: 'Contoh: Paket Bulanan 30 GB',
                    helperText: 'Wajib diisi',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Nama paket wajib diisi.'
                      : null,
                ),
                const SizedBox(height: 20),

                Text(
                  'Operator Telekomunikasi',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final name in _operators)
                      ChoiceChip(
                        label: Text(name),
                        selected: _operatorController.text.trim() == name,
                        onSelected: (_) => _operatorController.text = name,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _operatorController,
                  decoration: const InputDecoration(
                    labelText: 'Operator (Opsional)',
                    hintText: 'Pilih di atas atau ketik operator lain',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                _quotaRow(
                  controller: _totalQuotaController,
                  label: 'Jumlah Total Kuota',
                  hint: 'Contoh: 30',
                  validator: _validateTotal,
                  unit: _totalUnit,
                  onUnit: (u) => setState(() => _totalUnit = u),
                ),

                if (!_isEditing) ...[
                  const SizedBox(height: 16),
                  _quotaRow(
                    controller: _usedQuotaController,
                    label: 'Kuota Sudah Terpakai (Opsional)',
                    hint: 'Isi jika paket sudah terpakai sebelumnya',
                    validator: _validateUsed,
                    unit: _usedUnit,
                    onUnit: (u) => setState(() => _usedUnit = u),
                  ),
                ],
                const SizedBox(height: 20),

                Text(
                  'Masa Berlaku',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final days in _presetDays)
                      ChoiceChip(
                        label: Text('$days Hari'),
                        selected: _validityDays == days,
                        onSelected: (_) => setState(() => _applyValidity(days)),
                      ),
                    ChoiceChip(
                      label: const Text('Kustom'),
                      selected: _validityDays == null,
                      onSelected: (_) => setState(() => _validityDays = null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        _dateTile(
                          label: 'Tanggal Mulai',
                          date: _startDate,
                          onTap: _selectStartDate,
                        ),
                        const Divider(height: 1),
                        _dateTile(
                          label: _validityDays == null
                              ? 'Tanggal Berakhir'
                              : 'Berakhir Otomatis',
                          date: _endDate,
                          onTap: _validityDays == null ? _selectEndDate : null,
                          badge: _validityDays == null ? null : 'Auto-sync',
                        ),
                      ],
                    ),
                  ),
                ),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Jadikan paket utama'),
                  subtitle: Text(
                    archived
                        ? 'Paket yang diarsipkan tidak dapat diaktifkan.'
                        : endPassed
                        ? 'Paket yang sudah kedaluwarsa tidak dapat diaktifkan.'
                        : 'Hanya satu paket yang bisa menjadi paket utama.',
                  ),
                  value: _isActive && !archived && !endPassed,
                  onChanged: (archived || endPassed)
                      ? null
                      : (value) => setState(() => _isActive = value),
                ),
                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: provider.isLoading ? null : _savePackage,
                  icon: provider.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isEditing ? 'Simpan Perubahan' : 'Simpan Paket'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
