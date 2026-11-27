// Route '/usage/manual'. Argumen: DataPackage.
//
// Form input pemakaian manual hari ini. Penyimpanan memakai
// UsageProvider.saveManualToday() yang sudah tersedia; tidak ada logika baru.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../package/package_format.dart';
import '../package/package_theme.dart';
import 'usage_provider.dart';

enum _Unit { gb, mb }

class UsageManualPage extends StatefulWidget {
  const UsageManualPage({super.key});

  @override
  State<UsageManualPage> createState() => _UsageManualPageState();
}

class _UsageManualPageState extends State<UsageManualPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  DataPackage? _package;
  bool _initialized = false;
  bool _isSaving = false;
  _Unit _unit = _Unit.gb;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final argument = ModalRoute.of(context)?.settings.arguments;
    if (argument is DataPackage) _package = argument;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  int _toBytes(double value) =>
      (value * (_unit == _Unit.gb ? 1000000000 : 1000000)).round();

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Jumlah pemakaian wajib diisi.';
    }

    final number = _parse(value);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Jumlah pemakaian harus berupa angka lebih dari 0.';
    }

    // Pemakaian melebihi kuota tetap sah dicatat, jadi tidak ada batas atas.
    return null;
  }

  Future<void> _save() async {
    final package = _package;
    if (package == null) {
      _snack('Paket tidak ditemukan.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final bytes = _toBytes(_parse(_amountController.text)!);
    final provider = context.read<UsageProvider>();

    setState(() => _isSaving = true);
    await provider.saveManualToday(package, bytes);
    if (!mounted) return;

    setState(() => _isSaving = false);

    final error = provider.errorMessage;
    if (error != null) {
      _snack(error);
      return;
    }

    _snack('Pemakaian manual ${formatBytes(bytes)} disimpan.');
    Navigator.pop(context, true);
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Pemakaian Manual?'),
        content: const Text(
          'Catatan pemakaian manual hari ini akan dihapus sehingga pembacaan '
          'perangkat dipakai kembali untuk hari ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PkgPalette.of(context).danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _deleteToday() async {
    final package = _package;
    if (package == null) return;

    final confirmed = await _confirmDelete();
    if (!confirmed || !mounted) return;

    final provider = context.read<UsageProvider>();

    setState(() => _isSaving = true);
    await provider.deleteManualToday(package);
    if (!mounted) return;

    setState(() => _isSaving = false);

    final error = provider.errorMessage;
    _snack(error ?? 'Pemakaian manual hari ini dihapus.');
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

  Widget _unitToggle() {
    Widget segment(_Unit unit, String label) {
      final selected = _unit == unit;

      return Expanded(
        child: GestureDetector(
          onTap: _isSaving ? null : () => setState(() => _unit = unit),
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
      child: Row(children: [segment(_Unit.gb, 'GB'), segment(_Unit.mb, 'MB')]),
    );
  }

  Widget _infoBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PkgPalette.of(context).chip,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: PkgPalette.of(context).primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: PkgPalette.of(context).text,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = PkgPalette.of(context);
    final package = _package;

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: const PkgAppBar(title: 'Input Pemakaian Manual'),
      body: package == null
          ? Center(
              child: Text(
                'Paket tidak ditemukan.',
                style: TextStyle(color: pal.muted),
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text(
                    package.packageName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: pal.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Total kuota ${formatBytes(package.advertisedTotalQuotaBytes)}',
                    style: TextStyle(color: pal.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  PkgCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Pemakaian Hari Ini', trailing: 'Wajib diisi'),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _amountController,
                                enabled: !_isSaving,
                                style: TextStyle(fontSize: 18, color: pal.text),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9,.]'),
                                  ),
                                ],
                                decoration: _fieldDecoration(
                                  hint: '1,5',
                                  suffix: 'Besaran',
                                ),
                                validator: _validateAmount,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _unitToggle(),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _infoBox(
                          'Catatan manual hanya berlaku untuk hari ini dan '
                          'menggantikan pembacaan otomatis perangkat pada hari '
                          'yang sama, sehingga pemakaian tidak dihitung dua '
                          'kali. Nilai di atas total kuota tetap dapat '
                          'disimpan.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: pal.primary,
                        foregroundColor: pal.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(
                        _isSaving ? 'Menyimpan...' : 'Simpan Pemakaian',
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
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.danger,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isSaving ? null : _deleteToday,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text(
                        'Hapus Pemakaian Manual Hari Ini',
                        style: TextStyle(
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
                    child: TextButton(
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
  }
}
