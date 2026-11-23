import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format_utils.dart';
import '../../models/models.dart';
import '../../services/data_limit_service.dart';
import '../auth/auth_provider.dart';
import 'data_limit_provider.dart';

class DataLimitPage extends StatefulWidget {
  const DataLimitPage({super.key});

  @override
  State<DataLimitPage> createState() => _DataLimitPageState();
}

class _DataLimitPageState extends State<DataLimitPage> {
  DataPackage? _package;
  bool _loadScheduled = false;

  final TextEditingController _amountController = TextEditingController();

  bool _enabled = true;
  double _warnPercent = 80;
  String _unit = 'GB';
  bool _amountInvalid = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final argument = ModalRoute.of(context)?.settings.arguments;
    if (argument is DataPackage) _package = argument;

    if (_package != null && !_loadScheduled) {
      _loadScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final package = _package;
    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (package == null || userId == null) return;

    await context.read<DataLimitProvider>().load(package, userId);
    if (!mounted) return;
    _syncForm();
  }

  void _syncForm() {
    final setting = context.read<DataLimitProvider>().setting;
    final bytes = setting?.dailyLimitBytes;

    setState(() {
      _enabled = setting?.isEnabled ?? true;
      _warnPercent = (setting?.warnAtPercent ?? 80).clamp(50, 95).toDouble();
      _amountInvalid = false;

      if (bytes != null && bytes > 0) {
        if (bytes >= kBytesPerGB) {
          _unit = 'GB';
          _amountController.text = _formatAmount(bytes / kBytesPerGB);
        } else {
          _unit = 'MB';
          _amountController.text = _formatAmount(bytes / kBytesPerMB);
        }
      } else {
        _unit = 'GB';
        _amountController.clear();
      }
    });
  }

  String _formatAmount(double value) {
    final text = value.toStringAsFixed(2);
    return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  int? _parseAmount() {
    final raw = _amountController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;

    final value = double.tryParse(raw);
    if (value == null || value <= 0) return null;

    final multiplier = _unit == 'GB' ? kBytesPerGB : kBytesPerMB;
    return (value * multiplier).round();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final package = _package;
    final userId = context.read<AuthProvider>().currentUser?.uid;
    if (package == null || package.id == null || userId == null) return;

    final bytes = _parseAmount();
    if (_enabled && bytes == null) {
      setState(() => _amountInvalid = true);
      _snack('Batas harian harus berupa angka lebih dari 0.');
      return;
    }

    final provider = context.read<DataLimitProvider>();
    provider.clearError();

    final saved = await provider.save(
      packageId: package.id!,
      userId: userId,
      isEnabled: _enabled,
      dailyLimitBytes: bytes,
      warnAtPercent: _warnPercent.round(),
    );

    if (!mounted) return;

    if (saved) {
      _syncForm();
      _snack('Batas penggunaan data harian tersimpan.');
    } else {
      _snack(provider.errorMessage ?? 'Gagal menyimpan batas harian.');
    }
  }

  ({String label, Color color}) _statusFor(DataLimitProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    final evaluation = provider.evaluation;

    if (evaluation == null) {
      return (label: 'Memuat', color: scheme.outline);
    }

    return switch (evaluation.status) {
      DataLimitStatus.normal => (label: 'Aman', color: scheme.primary),
      DataLimitStatus.warning => (
        label: 'Mendekati batas',
        color: const Color(0xFFB26A00),
      ),
      DataLimitStatus.reached => (label: 'Batas tercapai', color: scheme.error),
      DataLimitStatus.exceeded => (
        label: 'Melewati batas',
        color: scheme.error,
      ),
      DataLimitStatus.noLimit => (
        label: 'Belum ada batas',
        color: scheme.outline,
      ),
      DataLimitStatus.disabled => (
        label: 'Peringatan nonaktif',
        color: scheme.outline,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final package = _package;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batas Penggunaan Harian'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: package == null
          ? const Center(child: Text('Paket tidak ditemukan.'))
          : Consumer<DataLimitProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.evaluation == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.errorMessage != null &&
                    provider.evaluation == null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(provider.errorMessage!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _summaryCard(package, provider),
                    const SizedBox(height: 16),
                    _formCard(provider),
                    const SizedBox(height: 16),
                    _notificationCard(provider),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: provider.isSaving ? null : _save,
                      icon: provider.isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Simpan Batas Harian'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Peringatan hanya berupa notifikasi lokal. DATAWISE tidak '
                      'mematikan data seluler secara otomatis.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _summaryCard(DataPackage package, DataLimitProvider provider) {
    final theme = Theme.of(context);
    final evaluation = provider.evaluation;
    final status = _statusFor(provider);

    final limitBytes = evaluation?.limitBytes;
    final percent = evaluation?.usagePercent;
    final progress = percent == null ? 0.0 : (percent / 100).clamp(0.0, 1.0);

    final remaining = evaluation?.remainingBytes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: status.color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    package.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(status.label),
                  labelStyle: TextStyle(color: status.color),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  percent == null ? '--' : '${percent.toStringAsFixed(0)}%',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'dari batas harian',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                color: status.color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 16),
            _infoRow('Pemakaian hari ini', formatBytes(provider.usedBytes)),
            const Divider(),
            _infoRow(
              'Batas harian',
              limitBytes == null ? 'Belum diatur' : formatBytes(limitBytes),
            ),
            if (remaining != null) ...[
              const Divider(),
              _infoRow(
                remaining >= 0 ? 'Sisa sebelum batas' : 'Melewati batas',
                formatBytes(remaining.abs()),
              ),
            ],
            if (provider.setting?.dailyLimitBytes == null &&
                limitBytes != null) ...[
              const SizedBox(height: 8),
              Text(
                'Batas mengikuti target harian Data Planner.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 16),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget _formCard(DataLimitProvider provider) {
    final theme = Theme.of(context);
    final busy = provider.isSaving;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pengaturan Batas Harian', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktifkan peringatan batas'),
              subtitle: const Text(
                'Peringatan lokal dikirim saat pemakaian mencapai ambang.',
              ),
              value: _enabled,
              onChanged: busy
                  ? null
                  : (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              enabled: _enabled && !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Batas harian',
                border: const OutlineInputBorder(),
                suffixText: _unit,
                errorText: _amountInvalid
                    ? 'Masukkan angka lebih dari 0.'
                    : null,
              ),
              onChanged: (_) {
                if (_amountInvalid) setState(() => _amountInvalid = false);
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'GB', label: Text('GB')),
                ButtonSegment(value: 'MB', label: Text('MB')),
              ],
              selected: {_unit},
              onSelectionChanged: _enabled && !busy
                  ? (selection) => setState(() => _unit = selection.first)
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ambang peringatan awal',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${_warnPercent.round()}%',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            Slider(
              value: _warnPercent,
              min: 50,
              max: 95,
              divisions: 45,
              label: '${_warnPercent.round()}%',
              onChanged: _enabled && !busy
                  ? (value) => setState(() => _warnPercent = value)
                  : null,
            ),
            Text(
              'Ambang 100% (batas tercapai) selalu aktif dan tidak dapat '
              'diturunkan.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationCard(DataLimitProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = provider.notificationsEnabled;

    return Card(
      child: ListTile(
        leading: Icon(
          enabled
              ? Icons.notifications_active
              : Icons.notifications_off_outlined,
          color: enabled ? scheme.primary : scheme.outline,
        ),
        title: const Text('Notifikasi lokal'),
        subtitle: Text(
          enabled
              ? 'Peringatan 80% dan 100% dikirim sebagai notifikasi lokal, '
                    'sekali per hari untuk ambang yang sama.'
              : 'Notifikasi dimatikan di Pengaturan. Peringatan tidak akan '
                    'dikirim sampai notifikasi diaktifkan kembali.',
        ),
      ),
    );
  }
}
