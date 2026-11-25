import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/format_utils.dart';
import '../../models/models.dart';
import '../../services/data_limit_service.dart';
import '../auth/auth_provider.dart';
import '../package/package_theme.dart';
import 'data_limit_provider.dart';

/// Halaman pengaturan Data Limit Warning.
///
/// Struktur visual mengikuti halaman "Tambah Paket": judul 22/w800, kartu
/// [PkgCard] bersudut 18, field berisi warna `field` dengan radius 14, chip
/// sumber batas, dan tombol utama 48 px.
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

  /// true = ikuti target harian Data Planner (batas manual dikosongkan).
  bool _usePlanner = true;
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

    final provider = context.read<DataLimitProvider>();
    await provider.load(package, userId);
    if (!mounted) return;
    _syncForm(provider);
  }

  void _syncForm(DataLimitProvider provider) {
    final setting = provider.setting;
    final bytes = setting?.dailyLimitBytes ?? 0;

    setState(() {
      _enabled = setting?.isEnabled ?? true;
      _warnPercent = (setting?.warnAtPercent ?? 80).clamp(50, 95).toDouble();
      _amountInvalid = false;
      _usePlanner = bytes <= 0;

      if (bytes > 0) {
        if (bytes >= kBytesPerGB) {
          _unit = 'GB';
          _amountController.text = _formatAmount(bytes / kBytesPerGB);
        } else {
          _unit = 'MB';
          _amountController.text = _formatAmount(bytes / kBytesPerMB);
        }
      } else {
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
    if (value == null || !value.isFinite || value <= 0) return null;

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

    final bytes = _usePlanner ? null : _parseAmount();

    if (_enabled && !_usePlanner && bytes == null) {
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
      _syncForm(provider);
      _snack(
        bytes == null
            ? 'Batas harian mengikuti target Data Planner.'
            : 'Batas penggunaan data harian tersimpan.',
      );
    } else {
      _snack(provider.errorMessage ?? 'Gagal menyimpan batas harian.');
    }
  }

  // ---------- Status & warna ----------

  ({String label, Color fg, Color bg}) _statusStyle(
    DataLimitProvider provider,
    PkgPalette pal,
  ) {
    final evaluation = provider.evaluation;

    if (evaluation == null) {
      return (label: 'Memuat', fg: pal.muted, bg: pal.chip);
    }

    return switch (evaluation.status) {
      DataLimitStatus.normal => (
        label: 'Aman',
        fg: pal.primary,
        bg: pal.accent,
      ),
      DataLimitStatus.warning => (
        label: 'Hampir mencapai target',
        fg: pal.warning,
        bg: pal.warningBg,
      ),
      DataLimitStatus.reached => (
        label: 'Mencapai batas',
        fg: pal.danger,
        bg: pal.dangerBg,
      ),
      DataLimitStatus.exceeded => (
        label: 'Melebihi batas',
        fg: pal.danger,
        bg: pal.dangerBg,
      ),
      DataLimitStatus.noLimit => (
        label: 'Belum ada batas',
        fg: pal.muted,
        bg: pal.chip,
      ),
      DataLimitStatus.disabled => (
        label: 'Peringatan nonaktif',
        fg: pal.muted,
        bg: pal.chip,
      ),
    };
  }

  // ---------- Widget bantu ----------

  Widget _label(String text, {String? trailing}) {
    final pal = PkgPalette.of(context);

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
                color: pal.text,
              ),
            ),
          ),
          if (trailing != null)
            Flexible(
              child: Text(
                trailing,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: pal.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool emphasize = false}) {
    final pal = PkgPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: pal.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: pal.text,
              fontSize: emphasize ? 15 : 14,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final pal = PkgPalette.of(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? pal.primary : pal.field,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? pal.onPrimary : pal.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? pal.onPrimary : pal.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unitToggle() {
    final pal = PkgPalette.of(context);

    Widget seg(String unit) {
      final selected = _unit == unit;

      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _unit = unit),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? pal.onPrimary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unit,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: selected ? pal.primary : pal.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 92,
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: pal.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [seg('GB'), seg('MB')]),
    );
  }

  Widget _sourceNotice(DataLimitProvider provider, PkgPalette pal) {
    final evaluation = provider.evaluation;
    final plannerTarget = provider.plannerDailyTargetBytes;
    final limit = evaluation?.limitBytes;

    final IconData icon;
    final String text;
    final Color fg;
    final Color bg;

    if (!_enabled) {
      icon = Icons.notifications_off_outlined;
      text =
          'Peringatan batas harian sedang dinonaktifkan. Tidak ada notifikasi '
          'yang dikirim, tetapi pemakaian tetap dicatat.';
      fg = pal.muted;
      bg = pal.field;
    } else if (provider.usesPlannerTarget) {
      icon = Icons.auto_awesome_outlined;
      text =
          'Batas berasal dari target harian Data Planner'
          '${plannerTarget != null ? ' (${formatBytes(plannerTarget)}/hari)' : ''}'
          '. Ubah sisa kuota atau masa aktif paket untuk menyesuaikannya.';
      fg = pal.primary;
      bg = pal.chip;
    } else if (provider.usesManualLimit) {
      icon = Icons.tune;
      text =
          'Batas ditentukan sendiri oleh Anda'
          '${limit != null ? ' (${formatBytes(limit)}/hari)' : ''}'
          '. Batas ini menggantikan target Data Planner.';
      fg = pal.primary;
      bg = pal.chip;
    } else {
      icon = Icons.info_outline;
      text =
          'Belum ada batas yang dapat dipakai. Atur batas manual atau pastikan '
          'paket aktif masih memiliki sisa kuota dan masa aktif.';
      fg = pal.muted;
      bg = pal.field;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Kartu ----------

  Widget _summaryCard(DataPackage package, DataLimitProvider provider) {
    final pal = PkgPalette.of(context);
    final evaluation = provider.evaluation;
    final status = _statusStyle(provider, pal);

    final limitBytes = evaluation?.limitBytes;
    final percent = evaluation?.usagePercent;
    final progress = percent == null ? 0.0 : (percent / 100).clamp(0.0, 1.0);
    final remaining = evaluation?.remainingBytes;
    final tone = status.fg;

    return PkgCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PkgIconBox(Icons.speed, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: pal.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Batas penggunaan harian',
                      style: TextStyle(color: pal.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PkgPill(status.label, bg: status.bg, fg: status.fg, dot: true),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                percent == null ? '--' : '${percent.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: tone,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  limitBytes == null
                      ? 'belum ada batas harian'
                      : 'dari ${formatBytes(limitBytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.muted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: tone,
              backgroundColor: pal.field,
            ),
          ),
          const SizedBox(height: 14),
          _infoRow('Pemakaian hari ini', formatBytes(provider.usedBytes)),
          Divider(color: pal.chip, height: 1),
          _infoRow(
            'Batas harian',
            limitBytes == null ? 'Belum diatur' : formatBytes(limitBytes),
            emphasize: true,
          ),
          if (remaining != null) ...[
            Divider(color: pal.chip, height: 1),
            _infoRow(
              remaining >= 0 ? 'Sisa sebelum batas' : 'Melewati batas',
              formatBytes(remaining.abs()),
            ),
          ],
          const SizedBox(height: 14),
          _sourceNotice(provider, pal),
        ],
      ),
    );
  }

  Widget _settingsCard(DataLimitProvider provider) {
    final pal = PkgPalette.of(context);
    final busy = provider.isSaving;
    final plannerTarget = provider.plannerDailyTargetBytes;

    return PkgCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pengaturan Batas',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: pal.text,
            ),
          ),
          const SizedBox(height: 14),
          _label('Sumber Batas Harian'),
          Row(
            children: [
              _modeChip(
                label: 'Data Planner',
                icon: Icons.auto_awesome_outlined,
                selected: _usePlanner,
                onTap: busy
                    ? () {}
                    : () => setState(() {
                        _usePlanner = true;
                        _amountInvalid = false;
                      }),
              ),
              const SizedBox(width: 8),
              _modeChip(
                label: 'Atur Sendiri',
                icon: Icons.edit_outlined,
                selected: !_usePlanner,
                onTap: busy
                    ? () {}
                    : () => setState(() {
                        _usePlanner = false;
                        _amountInvalid = false;
                      }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_usePlanner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.field,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                plannerTarget == null
                    ? 'Target Data Planner belum tersedia untuk paket ini.'
                    : 'Target harian saat ini ${formatBytes(plannerTarget)} '
                          '(${provider.planner?.remainingDays ?? 0} hari tersisa).',
                style: TextStyle(color: pal.muted, fontSize: 12),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    enabled: _enabled && !busy,
                    style: TextStyle(fontSize: 18, color: pal.text),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: '1,5',
                      hintStyle: TextStyle(color: pal.muted),
                      filled: true,
                      fillColor: pal.field,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: pal.primary, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: pal.danger),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: pal.danger, width: 1.5),
                      ),
                      errorText: _amountInvalid
                          ? 'Masukkan angka lebih dari 0.'
                          : null,
                    ),
                    onChanged: (_) {
                      if (_amountInvalid) {
                        setState(() => _amountInvalid = false);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _unitToggle(),
              ],
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: pal.field,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Text(
                        'Aktifkan peringatan',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: pal.text,
                        ),
                      ),
                      Text(
                        'Notifikasi dikirim saat pemakaian mencapai ambang.',
                        style: TextStyle(color: pal.muted, fontSize: 11.5),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => _enabled = value),
                  activeThumbColor: pal.onPrimary,
                  activeTrackColor: pal.primary,
                  inactiveThumbColor: pal.onPrimary,
                  inactiveTrackColor: pal.chip,
                  trackOutlineColor: WidgetStateProperty.all(
                    Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ambang peringatan awal',
                  style: TextStyle(color: pal.muted, fontSize: 12),
                ),
              ),
              Text(
                '${_warnPercent.round()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: pal.text,
                ),
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
            style: TextStyle(color: pal.muted, fontSize: 11.5, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(DataLimitProvider provider) {
    final pal = PkgPalette.of(context);
    final enabled = provider.notificationsEnabled;

    return PkgCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PkgIconBox(
            enabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            size: 40,
            bg: pal.field,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifikasi lokal',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: pal.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Peringatan dikirim sekali per hari untuk ambang yang '
                            'sama, termasuk saat aplikasi di latar belakang. '
                            'Pemeriksaan latar belakang mengikuti jadwal sistem '
                            '(minimal 15 menit), bukan pemantauan real-time.'
                      : 'Notifikasi dimatikan di Pengaturan. Peringatan tidak '
                            'akan dikirim sampai notifikasi diaktifkan kembali.',
                  style: TextStyle(
                    color: pal.muted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final package = _package;
    final pal = PkgPalette.of(context);

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: const PkgAppBar(title: 'Batas Penggunaan Harian'),
      body: package == null
          ? const Center(child: Text('Paket tidak ditemukan.'))
          : Consumer<DataLimitProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.evaluation == null) {
                  return Center(
                    child: CircularProgressIndicator(color: pal.primary),
                  );
                }

                if (provider.errorMessage != null &&
                    provider.evaluation == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            provider.errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: pal.text),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            style: FilledButton.styleFrom(
                              backgroundColor: pal.primary,
                              foregroundColor: pal.onPrimary,
                            ),
                            child: const Text('Coba lagi'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Batas Harian',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: pal.text,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Muat ulang',
                          onPressed: _load,
                          icon: Icon(Icons.refresh, color: pal.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _summaryCard(package, provider),
                    const SizedBox(height: 14),
                    _settingsCard(provider),
                    const SizedBox(height: 14),
                    _notificationCard(provider),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: pal.primary,
                          foregroundColor: pal.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: provider.isSaving ? null : _save,
                        icon: provider.isSaving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: pal.onPrimary,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Simpan Batas Harian'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Peringatan hanya berupa notifikasi lokal. DATAWISE tidak '
                      'mematikan data seluler secara otomatis.',
                      style: TextStyle(
                        color: pal.muted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
