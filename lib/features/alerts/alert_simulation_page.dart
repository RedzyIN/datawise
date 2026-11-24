// Halaman simulasi Smart Alerts. Hanya tersedia pada build debug.
//
// Tombol simulasi tidak pernah tampil pada build produksi karena halaman ini
// hanya dibuka dari Pengaturan ketika `kDebugMode` aktif dan tetap menolak
// merender isinya di build release.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/alert_simulation.dart';

class AlertSimulationPage extends StatefulWidget {
  const AlertSimulationPage({super.key});

  @override
  State<AlertSimulationPage> createState() => _AlertSimulationPageState();
}

class _AlertSimulationPageState extends State<AlertSimulationPage> {
  final List<AlertSimulationResult> _results = [];

  bool _running = false;

  Future<void> _run(AlertSimulationScenario scenario) async {
    setState(() => _running = true);

    final result = await context.read<AlertSimulator>().run(scenario);

    if (!mounted) return;

    setState(() {
      _results.removeWhere((item) => item.scenario == scenario);
      _results.add(result);
      _running = false;
    });
  }

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _results.clear();
    });

    final results = await context.read<AlertSimulator>().runAll();

    if (!mounted) return;

    setState(() {
      _results
        ..clear()
        ..addAll(results);
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final pal = AppPageColors.of(context);

    return Scaffold(
      backgroundColor: pal.background,
      appBar: AppBar(
        backgroundColor: pal.background,
        foregroundColor: pal.ink,
        title: const Text('Simulasi Smart Alert'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: pal.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: pal.line),
            ),
            child: Text(
              'Mode debug. Simulasi memakai AlertService produksi dengan data '
              'terkontrol di memori, sehingga database pengguna tidak berubah. '
              'Notifikasi yang diizinkan tetap dikirim ke perangkat.',
              style: TextStyle(fontSize: 12, height: 1.4, color: pal.muted),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _runAll,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: const Text('Jalankan semua simulasi'),
          ),
          const SizedBox(height: 20),
          ...AlertSimulationScenario.values.map(_buildScenarioTile),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Hasil',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: pal.ink,
              ),
            ),
            const SizedBox(height: 12),
            ..._results.map(_buildResultCard),
          ],
        ],
      ),
    );
  }

  Widget _buildScenarioTile(AlertSimulationScenario scenario) {
    final pal = AppPageColors.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(scenario.label, style: TextStyle(color: pal.ink)),
      subtitle: Text(
        'Picu event simulasi ini saja',
        style: TextStyle(fontSize: 12, color: pal.muted),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _running ? null : () => _run(scenario),
    );
  }

  Widget _buildResultCard(AlertSimulationResult result) {
    final pal = AppPageColors.of(context);
    final okColor = result.passed ? pal.primaryDeep : pal.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.passed ? Icons.check_circle : Icons.error,
                size: 18,
                color: okColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.scenario.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: pal.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(result.detail, style: TextStyle(fontSize: 12, color: pal.muted)),
          const SizedBox(height: 8),
          Text(
            'Notifikasi: ${result.notifications.join(', ')}',
            style: TextStyle(fontSize: 11, color: pal.muted),
          ),
          ...result.logs.map(
            (log) => Text(
              '• ${log.alertType} — ${log.message}',
              style: TextStyle(fontSize: 11, height: 1.4, color: pal.ink),
            ),
          ),
        ],
      ),
    );
  }
}
