import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_format.dart';
import 'package_provider.dart';
import 'package_theme.dart';
import 'quota_category_format.dart';
import 'quota_category_provider.dart';

enum _Unit { gb, mb }

/// Kategori yang disiapkan sebelum paket disimpan (mode tambah).
class _CategoryDraft {
  const _CategoryDraft({
    required this.name,
    required this.type,
    required this.capacityBytes,
  });

  final String name;
  final QuotaCategoryType type;
  final int capacityBytes;
}

/// Hasil editor kategori: simpan atau hapus.
class _CategoryEditorResult {
  const _CategoryEditorResult.save({
    required this.name,
    required this.type,
    required this.capacityBytes,
  }) : deleted = false;

  const _CategoryEditorResult.delete()
    : name = '',
      type = QuotaCategoryType.custom,
      capacityBytes = 0,
      deleted = true;

  final String name;
  final QuotaCategoryType type;
  final int capacityBytes;
  final bool deleted;
}

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

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _totalQuotaController = TextEditingController();

  /// Pemakaian yang sudah terjadi sebelum paket dicatat di DATAWISE.
  final _initialUsedController = TextEditingController(text: '0');

  DataPackage? _editing;
  bool _initialized = false;
  bool _isActive = false;

  String? _operator;
  bool _criticalReminder = true; // Hanya tampilan; belum disimpan.

  _Unit _totalUnit = _Unit.gb;
  _Unit _initialUnit = _Unit.gb;

  /// Kategori tambahan yang dibuat saat menambah paket. Disimpan ke database
  /// setelah paket berhasil dibuat.
  final List<_CategoryDraft> _drafts = [];

  /// null = kustom (tanggal berakhir dipilih manual).
  int? _validityDays = 30;

  DateTime _startDate = DateUtils.dateOnly(DateTime.now());
  late DateTime _endDate = _startDate.add(const Duration(days: 30));

  bool get _isEditing => _editing != null;

  String? get _editingPackageId => _editing?.id;

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

      final packageId = package.id;
      if (packageId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Membaca baseline pemakaian awal yang sudah tersimpan agar form
          // edit menampilkan nilai sebenarnya, bukan 0.
          context.read<PackageProvider>().loadUsageFor(package);
          context.read<QuotaCategoryProvider>().load(packageId);
        });
      }
    } else {
      _isActive = context.read<PackageProvider>().activePackage == null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalQuotaController.dispose();
    _initialUsedController.dispose();
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
      quotaBytesFromInput(value, inGigabytes: unit == _Unit.gb);

  int _totalBytes() {
    final parsed = _parse(_totalQuotaController.text);
    if (parsed == null || !parsed.isFinite || parsed <= 0) return 0;
    return _toBytes(parsed, _totalUnit);
  }

  /// Pemakaian awal dari input form (0 jika kosong atau tidak valid).
  int _initialUsedBytes() {
    final parsed = _parse(_initialUsedController.text);
    if (parsed == null || !parsed.isFinite || parsed <= 0) return 0;
    return quotaBytesFromInput(parsed, inGigabytes: _initialUnit == _Unit.gb);
  }

  /// Sisa kuota awal yang langsung dihitung dan ditampilkan di form.
  int _remainingInitialBytes() =>
      remainingInitialBytes(_totalBytes(), _initialUsedBytes());

  String? _validateInitialUsed(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null; // kosong dianggap 0

    final number = _parse(text);
    if (number == null || !number.isFinite) {
      return 'Kuota terpakai harus berupa angka.';
    }
    if (number < 0) {
      return 'Kuota terpakai tidak boleh negatif.';
    }

    final total = _totalBytes();
    final bytes = quotaBytesFromInput(
      number,
      inGigabytes: _initialUnit == _Unit.gb,
    );

    if (total > 0 && bytes > total) {
      return 'Kuota terpakai tidak boleh melebihi total kuota '
          '(${formatBytes(total)}).';
    }

    return null;
  }

  int _draftAllocatedBytes([int? excludeIndex]) {
    var total = 0;
    for (var i = 0; i < _drafts.length; i++) {
      if (i == excludeIndex) continue;
      total += _drafts[i].capacityBytes;
    }
    return total;
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
    if (value == null || value.trim().isEmpty) {
      return 'Total kuota wajib diisi.';
    }
    final number = _parse(value);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Total kuota harus berupa angka lebih dari 0.';
    }
    return null;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Kategori kuota ----------

  String _typeCode(QuotaCategoryType type) => switch (type) {
    QuotaCategoryType.main => 'MAIN',
    QuotaCategoryType.night => 'NIGHT',
    QuotaCategoryType.social => 'SOCIAL',
    QuotaCategoryType.appSpecific => 'APP_SPECIFIC',
    QuotaCategoryType.custom => 'CUSTOM',
  };

  Future<void> _openNewDraftCategory() async {
    final total = _totalBytes();
    if (total <= 0) {
      _snack('Isi jumlah total kuota terlebih dahulu.');
      return;
    }

    final remaining = total - _draftAllocatedBytes();
    if (remaining <= 0) {
      _snack('Sisa kuota utama tidak mencukupi.');
      return;
    }

    final result = await showModalBottomSheet<_CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PkgPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CategoryEditorSheet(
        title: 'Tambah Kategori',
        availableBytes: remaining,
      ),
    );

    if (result == null || result.deleted || !mounted) return;

    setState(() {
      _drafts.add(
        _CategoryDraft(
          name: result.name,
          type: result.type,
          capacityBytes: result.capacityBytes,
        ),
      );
    });
  }

  Future<void> _editDraftCategory(int index) async {
    final draft = _drafts[index];
    final remaining = _totalBytes() - _draftAllocatedBytes(index);
    if (remaining <= 0) {
      _snack('Sisa kuota utama tidak mencukupi.');
      return;
    }

    final result = await showModalBottomSheet<_CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PkgPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CategoryEditorSheet(
        title: 'Ubah Kategori',
        availableBytes: remaining,
        initialName: draft.name,
        initialType: draft.type,
        initialCapacityBytes: draft.capacityBytes,
        allowDelete: true,
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      if (result.deleted) {
        _drafts.removeAt(index);
      } else {
        _drafts[index] = _CategoryDraft(
          name: result.name,
          type: result.type,
          capacityBytes: result.capacityBytes,
        );
      }
    });
  }

  Future<void> _openNewSavedCategory(DataPackage package) async {
    final provider = context.read<QuotaCategoryProvider>();
    if (provider.mainCategory == null) {
      _snack('Kategori utama paket tidak ditemukan.');
      return;
    }

    final result = await showModalBottomSheet<_CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PkgPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CategoryEditorSheet(
        title: 'Tambah Kategori',
        availableBytes: provider.mainCapacityBytes,
      ),
    );

    if (result == null || result.deleted || !mounted) return;

    final packageId = package.id;
    if (packageId == null) return;

    provider.clearError();
    final success = await provider.add(
      QuotaCategory(
        packageId: packageId,
        categoryName: result.name,
        categoryType: result.type,
        capacityBytes: result.capacityBytes,
        isEnabled: true,
        createdAt: DateTime.now(),
      ),
    );

    if (!mounted) return;
    if (!success) {
      _snack(provider.errorMessage ?? 'Gagal menyimpan kategori kuota.');
    }
  }

  Future<void> _editSavedCategory(QuotaCategory category) async {
    final packageId = _editingPackageId;
    if (packageId == null) return;

    final provider = context.read<QuotaCategoryProvider>();
    final result = await showModalBottomSheet<_CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PkgPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CategoryEditorSheet(
        title: 'Ubah Kategori',
        availableBytes: provider.mainCapacityBytes + category.capacityBytes,
        initialName: category.categoryName,
        initialType: category.categoryType,
        initialCapacityBytes: category.capacityBytes,
        allowDelete: true,
      ),
    );

    if (result == null || !mounted) return;

    provider.clearError();

    final bool success;
    if (result.deleted) {
      success = await provider.delete(category.id!);
    } else {
      success = await provider.update(
        category.copyWith(
          categoryName: result.name,
          capacityBytes: result.capacityBytes,
        ),
      );
    }

    if (!mounted) return;
    if (!success) {
      _snack(provider.errorMessage ?? 'Gagal menyimpan kategori kuota.');
    }
  }

  Future<void> _savePackage() async {
    if (!_formKey.currentState!.validate()) return;

    if (_drafts.isNotEmpty) {
      final total = _totalBytes();
      if (total <= 0 || _draftAllocatedBytes() >= total) {
        _snack('Total kuota tidak cukup untuk menampung kategori tambahan.');
        return;
      }
    }

    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      _snack('Pengguna belum terautentikasi.');
      return;
    }

    final totalBytes = _toBytes(
      _parse(_totalQuotaController.text)!,
      _totalUnit,
    );
    final initialUsedBytes = _isEditing ? 0 : _initialUsedBytes();

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
    provider.clearError();

    // Draft kategori ikut dikirim bersama paket agar repository menyimpannya
    // dalam satu transaksi. ID paket diisi oleh repository saat membuat paket.
    final draftCategories = [
      for (final draft in _drafts)
        QuotaCategory(
          packageId: package.id ?? '',
          categoryName: draft.name,
          categoryType: draft.type,
          capacityBytes: draft.capacityBytes,
          isEnabled: true,
          createdAt: now,
        ),
    ];

    final success = _isEditing
        ? await provider.updatePackage(package)
        : await provider.addPackage(
            package,
            initialUsedBytes: initialUsedBytes,
            categories: draftCategories,
          );

    if (!mounted) return;

    if (!success) {
      // Draft sengaja dipertahankan supaya pengguna dapat mencoba lagi tanpa
      // membuat paket atau kategori duplikat.
      _snack(provider.errorMessage ?? 'Gagal menyimpan paket.');
      return;
    }

    final packageId = _editingPackageId;
    if (_isEditing && packageId != null) {
      await context.read<QuotaCategoryProvider>().load(packageId);
      if (!mounted) return;
    }

    Navigator.pop(context, true);
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
      suffixStyle: TextStyle(color: PkgPalette.of(context).muted, fontSize: 12),
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

  Widget _unitToggle(_Unit value, ValueChanged<_Unit> onChanged) {
    Widget seg(_Unit u, String label) {
      final selected = value == u;

      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(u),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? PkgPalette.of(context).onPrimary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: selected
                    ? PkgPalette.of(context).primary
                    : PkgPalette.of(context).muted,
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
        color: PkgPalette.of(context).field,
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
    ValueChanged<String>? onChanged,
    bool showSuffix = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            style: TextStyle(fontSize: 18, color: PkgPalette.of(context).text),
            decoration: _fieldDecoration(
              hint: hint,
              suffix: showSuffix ? 'Besaran' : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            onChanged: onChanged,
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
          color: selected
              ? PkgPalette.of(context).primary
              : PkgPalette.of(context).field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: PkgPalette.of(context).accent,
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
                color: selected
                    ? PkgPalette.of(context).onPrimary
                    : PkgPalette.of(context).muted,
              ),
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
            color: selected
                ? PkgPalette.of(context).primary
                : PkgPalette.of(context).field,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: selected
                  ? PkgPalette.of(context).onPrimary
                  : PkgPalette.of(context).muted,
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
            style: TextStyle(color: PkgPalette.of(context).muted, fontSize: 12),
          ),
          Text(
            formatDate(date),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: bold
                  ? PkgPalette.of(context).primary
                  : PkgPalette.of(context).text,
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
          decoration: BoxDecoration(
            color: PkgPalette.of(context).chip,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.edit_calendar,
            color: PkgPalette.of(context).primary,
            size: 20,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PkgPalette.of(context).field,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month,
                color: PkgPalette.of(context).primary,
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
                Expanded(child: Divider(color: PkgPalette.of(context).chip)),
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: PkgPalette.of(context).primary,
                ),
                Expanded(child: Divider(color: PkgPalette.of(context).chip)),
                _dot(),
              ],
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.event_available,
                color: PkgPalette.of(context).primary,
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
    decoration: BoxDecoration(
      color: PkgPalette.of(context).primary,
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
      ),
    );
  }

  /// Bagian "Kuota Sudah Terpakai".
  ///
  /// Saat menambah paket, nilainya menjadi baseline pemakaian yang disimpan
  /// sebagai satu catatan MANUAL_TOTAL. Saat mengedit paket, nilainya hanya
  /// ditampilkan karena baseline yang sudah tercatat tidak boleh dihitung ulang.
  Widget _initialUsageSection(PackageProvider provider) {
    final pal = PkgPalette.of(context);

    if (_isEditing) {
      final baseline = provider.initialUsedFor(_editingPackageId);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Kuota Sudah Terpakai', trailing: 'Tersimpan'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pal.field,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const PkgIconBox(Icons.history, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pemakaian awal ${formatBytes(baseline)} sudah tercatat '
                    'sebagai bagian dari pemakaian paket ini dan tidak diubah '
                    'saat paket diedit.',
                    style: TextStyle(
                      color: pal.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Kuota Sudah Terpakai', trailing: 'Opsional'),
        Text(
          'Masukkan jumlah kuota yang sudah digunakan sebelum paket ini '
          'dicatat di DATAWISE. Isi 0 jika paket masih baru.',
          style: TextStyle(color: pal.muted, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 10),
        _quotaRow(
          controller: _initialUsedController,
          hint: '0',
          validator: _validateInitialUsed,
          unit: _initialUnit,
          onUnit: (u) => setState(() => _initialUnit = u),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: pal.chip,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.savings_outlined, size: 18, color: pal.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sisa kuota awal',
                  style: TextStyle(
                    color: pal.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                formatBytes(_remainingInitialBytes()),
                style: TextStyle(
                  color: pal.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Tinggi baris kategori dikunci supaya baris tidak mengempis (flat) saat
  /// area layar menyusut, misalnya ketika keyboard terbuka.
  static const double _categoryRowHeight = 40;

  /// Satu baris kategori. Baris sengaja tidak punya latar sendiri agar semua
  /// baris menyatu dalam satu kotak (lihat [_categoryGroup]).
  Widget _categoryRow({
    required String name,
    required QuotaCategoryType type,
    required int capacityBytes,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: _categoryRowHeight,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$name (${_typeCode(type)})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: PkgPalette.of(context).text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatBytes(capacityBytes),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: PkgPalette.of(context).text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Satu kotak untuk seluruh baris kategori, sesuai desain.
  Widget _categoryGroup(List<Widget> rows) {
    return Material(
      color: PkgPalette.of(context).field,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }

  Widget _categoryMessage(String message) {
    return SizedBox(
      height: _categoryRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: PkgPalette.of(context).muted, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _categoryList({
    required int count,
    required List<Widget> rows,
    required VoidCallback? onManage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pembagian Kategori Kuota',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: PkgPalette.of(context).text,
                ),
              ),
            ),
            Text(
              '$count Kategori',
              style: TextStyle(
                color: PkgPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _categoryGroup(rows),
        const SizedBox(height: 10),
        InkWell(
          onTap: onManage,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PkgPalette.of(context).chip,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.tune,
                  size: 18,
                  color: PkgPalette.of(context).primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Atur Kategori & Aturan Kuota',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: PkgPalette.of(context).primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _draftCategorySection() {
    final total = _totalBytes();
    final allocated = _draftAllocatedBytes();
    final mainBytes = total > allocated ? total - allocated : 0;

    return _categoryList(
      count: _drafts.length + 1,
      rows: [
        _categoryRow(
          name: 'Kuota Utama',
          type: QuotaCategoryType.main,
          capacityBytes: mainBytes,
        ),
        for (var i = 0; i < _drafts.length; i++)
          _categoryRow(
            name: _drafts[i].name,
            type: _drafts[i].type,
            capacityBytes: _drafts[i].capacityBytes,
            onTap: () => _editDraftCategory(i),
          ),
      ],
      onManage: _openNewDraftCategory,
    );
  }

  Widget _savedCategorySection(
    DataPackage package,
    QuotaCategoryProvider provider,
  ) {
    final main = provider.mainCategory;
    final additional = provider.additionalCategories;

    return _categoryList(
      count: provider.categories.length,
      rows: [
        if (provider.isLoading && provider.categories.isEmpty)
          _categoryMessage('Memuat kategori...')
        else ...[
          _categoryRow(
            name: main?.categoryName ?? 'Kuota Utama',
            type: QuotaCategoryType.main,
            capacityBytes: main?.capacityBytes ?? 0,
          ),
          for (final category in additional)
            _categoryRow(
              name: category.categoryName,
              type: category.categoryType,
              capacityBytes: category.capacityBytes,
              onTap: provider.isLoading
                  ? null
                  : () => _editSavedCategory(category),
            ),
        ],
      ],
      onManage: provider.isLoading
          ? null
          : () => _openNewSavedCategory(package),
    );
  }

  @override
  Widget build(BuildContext context) {
    final archived = _editing?.status == PackageStatus.archived;
    final endPassed = _endDate.isBefore(DateUtils.dateOnly(DateTime.now()));

    return Consumer2<PackageProvider, QuotaCategoryProvider>(
      builder: (context, provider, categoryProvider, child) {
        return Scaffold(
          backgroundColor: PkgPalette.of(context).bg,
          appBar: const PkgAppBar(title: 'Paket Kuota'),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditing ? 'Ubah Paket Kuota' : 'Tambah Paket Kuota',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: PkgPalette.of(context).text,
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
                          color: PkgPalette.of(context).dangerBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Batal',
                          style: TextStyle(
                            color: PkgPalette.of(context).danger,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Kartu 1: nama dan operator
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Nama Paket', trailing: 'Wajib diisi'),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(
                          fontSize: 16,
                          color: PkgPalette.of(context).text,
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
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Kartu 2: total kuota dan kategori
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Jumlah Total Kuota Tertera'),
                      _quotaRow(
                        controller: _totalQuotaController,
                        hint: '30',
                        validator: _validateTotal,
                        unit: _totalUnit,
                        onUnit: (u) => setState(() => _totalUnit = u),
                        onChanged: (_) => setState(() {}),
                        showSuffix: true,
                      ),
                      const SizedBox(height: 18),
                      _initialUsageSection(provider),
                      const SizedBox(height: 18),
                      if (_isEditing && _editing != null)
                        _savedCategorySection(_editing!, categoryProvider)
                      else
                        _draftCategorySection(),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Kartu 3: masa berlaku
                PkgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      backgroundColor: PkgPalette.of(context).primary,
                      foregroundColor: PkgPalette.of(context).onPrimary,
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
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PkgPalette.of(context).onPrimary,
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

/// Editor kategori sederhana yang dipakai di form paket.
class _CategoryEditorSheet extends StatefulWidget {
  const _CategoryEditorSheet({
    required this.title,
    required this.availableBytes,
    this.initialName,
    this.initialType,
    this.initialCapacityBytes,
    this.allowDelete = false,
  });

  final String title;
  final int availableBytes;
  final String? initialName;
  final QuotaCategoryType? initialType;
  final int? initialCapacityBytes;
  final bool allowDelete;

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  static const _types = [
    QuotaCategoryType.night,
    QuotaCategoryType.social,
    QuotaCategoryType.appSpecific,
    QuotaCategoryType.custom,
  ];

  final _nameController = TextEditingController();
  final _capacityController = TextEditingController();

  QuotaCategoryType _type = QuotaCategoryType.night;
  _Unit _unit = _Unit.gb;
  String? _error;

  @override
  void initState() {
    super.initState();

    if (widget.initialName != null) _nameController.text = widget.initialName!;
    if (widget.initialType != null &&
        widget.initialType != QuotaCategoryType.main) {
      _type = widget.initialType!;
    }

    final bytes = widget.initialCapacityBytes;
    if (bytes != null) {
      if (bytes >= 1000000000) {
        _unit = _Unit.gb;
        _capacityController.text = (bytes / 1000000000)
            .toStringAsFixed(2)
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
      } else {
        _unit = _Unit.mb;
        _capacityController.text = (bytes / 1000000)
            .toStringAsFixed(2)
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), '');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  int _toBytes(double value, _Unit unit) =>
      (value * (unit == _Unit.gb ? 1000000000 : 1000000)).round();

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama kategori wajib diisi.');
      return;
    }

    final value = double.tryParse(
      _capacityController.text.trim().replaceAll(',', '.'),
    );
    if (value == null || !value.isFinite || value <= 0) {
      setState(() => _error = 'Kapasitas harus berupa angka lebih dari 0.');
      return;
    }

    final bytes = _toBytes(value, _unit);
    if (bytes >= widget.availableBytes) {
      setState(() {
        _error =
            'Kapasitas harus lebih kecil dari ${formatBytes(widget.availableBytes)}.';
      });
      return;
    }

    Navigator.pop(
      context,
      _CategoryEditorResult.save(name: name, type: _type, capacityBytes: bytes),
    );
  }

  void _delete() {
    Navigator.pop(context, const _CategoryEditorResult.delete());
  }

  Widget _typeChip(QuotaCategoryType type) {
    final selected = _type == type;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = type),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? PkgPalette.of(context).accent
                : PkgPalette.of(context).field,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                quotaCategoryTypeIcon(type),
                size: 16,
                color: selected
                    ? PkgPalette.of(context).text
                    : PkgPalette.of(context).muted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  quotaCategoryTypeLabel(type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? PkgPalette.of(context).text
                        : PkgPalette.of(context).muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unitSeg(_Unit unit, String label) {
    final selected = _unit == unit;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _unit = unit),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? PkgPalette.of(context).onPrimary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: selected
                  ? PkgPalette.of(context).primary
                  : PkgPalette.of(context).muted,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: PkgPalette.of(context).text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: PkgPalette.of(context).muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: _typeChip(_types[0])),
                  const SizedBox(width: 8),
                  Expanded(child: _typeChip(_types[1])),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _typeChip(_types[2])),
                  const SizedBox(width: 8),
                  Expanded(child: _typeChip(_types[3])),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                style: TextStyle(
                  fontSize: 15,
                  color: PkgPalette.of(context).text,
                ),
                decoration: InputDecoration(
                  hintText: 'Nama kategori',
                  filled: true,
                  fillColor: PkgPalette.of(context).field,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: const OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _capacityController,
                      style: TextStyle(
                        fontSize: 18,
                        color: PkgPalette.of(context).text,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                      ],
                      decoration: InputDecoration(
                        hintText: '5',
                        suffixText: 'Besaran',
                        suffixStyle: TextStyle(
                          color: PkgPalette.of(context).muted,
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: PkgPalette.of(context).field,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: const OutlineInputBorder(
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 92,
                    height: 44,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: PkgPalette.of(context).field,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _unitSeg(_Unit.gb, 'GB'),
                        _unitSeg(_Unit.mb, 'MB'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Sisa kuota utama yang dapat dialokasikan: '
                '${formatBytes(widget.availableBytes)}.',
                style: TextStyle(
                  color: PkgPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: TextStyle(
                    color: PkgPalette.of(context).danger,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.allowDelete) ...[
                    GestureDetector(
                      onTap: _delete,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: PkgPalette.of(context).dangerBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.delete_outline,
                          color: PkgPalette.of(context).danger,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: PkgPalette.of(context).primary,
                          foregroundColor: PkgPalette.of(context).onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _submit,
                        child: const Text(
                          'Simpan Kategori',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
