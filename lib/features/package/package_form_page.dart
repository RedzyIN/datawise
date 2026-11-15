import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_provider.dart';
import '../../models/models.dart';
import 'package_provider.dart';

class PackageFormPage extends StatefulWidget {
  const PackageFormPage({super.key});

  @override
  State<PackageFormPage> createState() => _PackageFormPageState();
}

class _PackageFormPageState extends State<PackageFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _operatorController = TextEditingController();
  final _totalQuotaController = TextEditingController();
  final _initialUsedController = TextEditingController(text: '0');
  final _priceController = TextEditingController();

  DataPackage? _editing;
  bool _initialized = false;
  bool _isActive = false;

  DateTime _startDate = DateUtils.dateOnly(DateTime.now());
  DateTime _endDate = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 30)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;
    _initialized = true;

    _editing = ModalRoute.of(context)?.settings.arguments as DataPackage?;

    if (_editing != null) {
      final package = _editing!;

      _nameController.text = package.name;
      _operatorController.text = package.operator;
      _totalQuotaController.text = (package.totalBytes / 1000000000).toString();
      _initialUsedController.text = (package.initialUsedBytes / 1000000000)
          .toString();
      _priceController.text = package.price?.toString() ?? '';

      _startDate = DateUtils.dateOnly(package.startDate);
      _endDate = DateUtils.dateOnly(package.endDate);
      _isActive = package.isActive;
    } else {
      final provider = context.read<PackageProvider>();
      _isActive = provider.activePackage == null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _operatorController.dispose();
    _totalQuotaController.dispose();
    _initialUsedController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
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

      // Jika tanggal mulai melewati tanggal berakhir,
      // sesuaikan tanggal berakhir menjadi 30 hari setelahnya.
      if (!_endDate.isAfter(_startDate)) {
        _endDate = _startDate.add(const Duration(days: 30));
      }
    });
  }

  Future<void> _selectEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate.add(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );

    if (selected == null || !mounted) return;

    setState(() {
      _endDate = DateUtils.dateOnly(selected);
    });
  }

  String? _requiredText(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label wajib diisi.';
    }
    return null;
  }

  String? _validateQuota(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label wajib diisi.';
    }

    final number = double.tryParse(value.replaceAll(',', '.'));

    if (number == null || !number.isFinite || number < 0) {
      return '$label harus berupa angka yang valid.';
    }

    return null;
  }

  String? _validateTotalQuota(String? value) {
    final error = _validateQuota(value, 'Total kuota');
    if (error != null) return error;

    final number = double.parse(value!.replaceAll(',', '.'));

    if (number <= 0) {
      return 'Total kuota harus lebih dari 0 GB.';
    }

    return null;
  }

  String? _validatePrice(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final price = int.tryParse(value);

    if (price == null || price < 0) {
      return 'Harga harus berupa bilangan bulat positif.';
    }

    return null;
  }

  Future<void> _savePackage() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final userId = auth.currentUser?.uid;

    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengguna belum terautentikasi.')),
      );
      return;
    }

    final totalQuota = double.parse(
      _totalQuotaController.text.replaceAll(',', '.'),
    );

    final initialUsed = double.parse(
      _initialUsedController.text.replaceAll(',', '.'),
    );

    final totalBytes = (totalQuota * 1000000000).round();
    final initialUsedBytes = (initialUsed * 1000000000).round();

    final now = DateTime.now();

    final package = DataPackage(
      id: _editing?.id,
      userId: userId,
      name: _nameController.text.trim(),
      operator: _operatorController.text.trim(),
      totalBytes: totalBytes,
      initialUsedBytes: initialUsedBytes,
      startDate: _startDate,
      endDate: _endDate,
      price: _priceController.text.trim().isEmpty
          ? null
          : int.parse(_priceController.text),
      isActive: _isActive,
      createdAt: _editing?.createdAt ?? now,
      updatedAt: now,
    );

    final provider = context.read<PackageProvider>();

    final success = _editing == null
        ? await provider.addPackage(package)
        : await provider.updatePackage(package);

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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime date,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.calendar_today),
            label: Text(_formatDate(date)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PackageProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_editing == null ? 'Tambah Paket' : 'Ubah Paket'),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'Nama Paket',
                  hint: 'Contoh: Internet 30 Hari',
                  validator: (value) => _requiredText(value, 'Nama paket'),
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _operatorController,
                  label: 'Operator',
                  hint: 'Contoh: Telkomsel',
                  validator: (value) => _requiredText(value, 'Operator'),
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _totalQuotaController,
                  label: 'Total Kuota (GB)',
                  hint: 'Contoh: 20',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _validateTotalQuota,
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _initialUsedController,
                  label: 'Pemakaian Awal (GB)',
                  hint: 'Contoh: 2',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final error = _validateQuota(value, 'Pemakaian awal');

                    if (error != null) return error;

                    final used = double.parse(value!.replaceAll(',', '.'));

                    final total = double.parse(
                      _totalQuotaController.text.replaceAll(',', '.'),
                    );

                    if (used > total) {
                      return 'Pemakaian awal melebihi total kuota.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: _buildDateField(
                        label: 'Tanggal Mulai',
                        date: _startDate,
                        onPressed: _selectStartDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateField(
                        label: 'Tanggal Berakhir',
                        date: _endDate,
                        onPressed: _selectEndDate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _priceController,
                  label: 'Harga Paket (Opsional)',
                  hint: 'Contoh: 50000',
                  keyboardType: TextInputType.number,
                  validator: _validatePrice,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 16),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Jadikan paket utama'),
                  subtitle: const Text(
                    'Paket utama digunakan sebagai paket aktif.',
                  ),
                  value: _isActive,
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: provider.isLoading ? null : _savePackage,
                  child: provider.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _editing == null
                              ? 'Simpan Paket'
                              : 'Simpan Perubahan',
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
