// PEMILIK: Anggota D. Tab Beranda di /home. Hanya menampilkan data dari Provider.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/routes.dart';
import '../../features/auth/auth_provider.dart';
import 'dashboard_provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _requestedInitialLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedInitialLoad) return;
    _requestedInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) context.read<DashboardProvider>().refresh(user.uid);
    });
  }

  Future<void> _refresh() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user != null) await context.read<DashboardProvider>().refresh(user.uid);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, data, _) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DATAWISE', style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4,
                      )),
                      const SizedBox(height: 4),
                      const Text('Dashboard', style: TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w800,
                      )),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Muat ulang',
                  onPressed: data.isRefreshing ? null : _refresh,
                  icon: data.isRefreshing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Notifikasi',
                  onPressed: () => _showNotifications(context),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (data.loadState == DashboardLoad.loading && data.package == null)
              const _LoadingCard()
            else if (data.loadState == DashboardLoad.error && data.package == null)
              _MessageCard(
                icon: Icons.error_outline,
                title: 'Dashboard belum dapat dimuat',
                message: data.errorMessage ?? 'Terjadi kesalahan.',
                action: TextButton(onPressed: _refresh, child: const Text('Coba lagi')),
              )
            else if (data.loadState == DashboardLoad.noPackage || data.package == null)
              _MessageCard(
                icon: Icons.sim_card_outlined,
                title: 'Belum ada paket aktif',
                message: 'Tambahkan paket data untuk mulai memantau pemakaian internet.',
                action: FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(context, Routes.packageForm),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah Paket'),
                ),
              )
            else ...[
              _packageCard(context, data),
              const SizedBox(height: 14),
              _quotaCard(context, data),
              const SizedBox(height: 14),
              _targetCard(context, data),
              const SizedBox(height: 14),
              _chartCard(context, data),
              const SizedBox(height: 14),
              _permissionCard(context, data),
              const SizedBox(height: 14),
              _quickActions(context, data),
              const SizedBox(height: 12),
              _lastUpdated(data),
              if (data.loadState == DashboardLoad.error && data.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(data.errorMessage!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _packageCard(BuildContext context, DashboardProvider data) {
    final p = data.package!;
    final days = p.endDate.difference(DateTime.now()).inDays;
    return _Card(
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.sim_card_rounded, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('${p.operator} • Berlaku sampai ${formatDate(p.endDate)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          )),
          _Pill(label: days < 0 ? 'Kedaluwarsa' : '${days + 1} hari lagi',
              color: days < 0 ? Colors.red : Colors.green),
        ],
      ),
    );
  }

  Widget _quotaCard(BuildContext context, DashboardProvider data) {
    final p = data.package!;
    final percent = p.totalBytes <= 0 ? 0.0 :
        (data.totalUsedBytes / p.totalBytes * 100).clamp(0.0, 100.0);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kuota utama', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Text(formatBytes(data.remainingBytes),
                style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900))),
            Text('dari ${formatBytes(p.totalBytes)}', style: const TextStyle(color: Colors.black54)),
          ]),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(value: percent / 100, minHeight: 10),
          ),
          const SizedBox(height: 9),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${percent.toStringAsFixed(1)}% terpakai',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${formatBytes(data.totalUsedBytes)} digunakan',
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
            const SizedBox(width: 7),
            const Expanded(child: Text('Angka pemakaian merupakan catatan perangkat/estimasi, bukan data resmi operator.',
                style: TextStyle(color: Colors.black54, fontSize: 11))),
          ]),
        ],
      ),
    );
  }

  Widget _targetCard(BuildContext context, DashboardProvider data) {
    final plan = data.plan;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Target pemakaian', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Metric(
            label: 'Pemakaian hari ini',
            value: formatBytes(data.todayUsedBytes),
            icon: Icons.today_outlined,
          )),
          const SizedBox(width: 10),
          Expanded(child: _Metric(
            label: 'Target harian',
            value: plan?.dailyTargetBytes == null ? 'Belum tersedia' : formatBytes(plan!.dailyTargetBytes!),
            icon: Icons.flag_outlined,
          )),
        ]),
        const SizedBox(height: 8),
        Text(
          plan == null ? 'Target harian dan mingguan akan tampil setelah PlannerService tersedia.'
              : 'Target mingguan: ${plan.weeklyTargetBytes == null ? '-' : formatBytes(plan.weeklyTargetBytes!)}',
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ]),
    );
  }

  Widget _chartCard(BuildContext context, DashboardProvider data) {
    final now = DateTime.now();
    final values = List<int>.generate(7, (i) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i));
      return data.dailyUsage[day] ?? 0;
    });
    final maxValue = values.fold<int>(0, (a, b) => a > b ? a : b);
    return _Card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pemakaian 7 hari terakhir', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 18),
        SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final fraction = maxValue == 0 ? 0.04 : (values[i] / maxValue).clamp(.04, 1.0);
              final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i));
              const labels = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(values[i] == 0 ? '-' : formatBytes(values[i]),
                      style: const TextStyle(fontSize: 9, color: Colors.black54)),
                  const SizedBox(height: 5),
                  Expanded(child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: fraction,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: .75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  )),
                  const SizedBox(height: 6),
                  Text(labels[day.weekday % 7], style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ]),
              ));
            }),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Sumber: catatan pemakaian harian yang tersimpan.',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    ));
  }

  Widget _permissionCard(BuildContext context, DashboardProvider data) {
    final ok = data.hasUsagePermission;
    return _Card(child: Row(children: [
      Icon(ok ? Icons.verified_user_outlined : Icons.lock_outline,
          color: ok ? Colors.green : Colors.orange, size: 25),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Akses penggunaan aplikasi', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(ok ? 'Izin Usage Access aktif' : 'Izin Usage Access belum aktif',
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ])),
      if (!ok) TextButton(
        onPressed: () => _showPermissionInfo(context),
        child: const Text('Info'),
      ),
    ]));
  }

  Widget _quickActions(BuildContext context, DashboardProvider data) {
    return Row(children: [
      Expanded(child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(context, Routes.usageManual, arguments: data.package),
        icon: const Icon(Icons.edit_note),
        label: const Text('Input pemakaian'),
      )),
      const SizedBox(width: 10),
      Expanded(child: OutlinedButton.icon(
        onPressed: () {
          final id = data.package?.id;
          if (id != null) Navigator.pushNamed(context, Routes.packageDetail, arguments: id);
        },
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Detail paket'),
      )),
    ]);
  }

  Widget _lastUpdated(DashboardProvider data) {
    final updated = data.lastUpdatedAt;
    return Center(child: Text(
      updated == null ? 'Belum pernah diperbarui' :
        'Terakhir diperbarui: ${updated.day.toString().padLeft(2, '0')}/${updated.month.toString().padLeft(2, '0')} ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}',
      style: const TextStyle(color: Colors.black45, fontSize: 11),
    ));
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.notifications_none, size: 36),
          SizedBox(height: 10),
          Text('Notifikasi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          SizedBox(height: 8),
          Text('Belum ada notifikasi penggunaan kuota.'),
        ]),
      ),
    );
  }

  void _showPermissionInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izin Usage Access'),
        content: const Text('Aktifkan akses penggunaan aplikasi melalui Pengaturan Android agar DATAWISE dapat membaca statistik penggunaan jaringan. Jika belum tersedia, pemakaian dapat dicatat secara manual.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Mengerti'))],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [BoxShadow(color: Color(0x0A17324D), blurRadius: 16, offset: Offset(0, 5))],
    ),
    child: child,
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFF4F8FC), borderRadius: BorderRadius.circular(13)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: Colors.black54, fontSize: 11)),
    ]),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => const _MessageCard(
    icon: Icons.hourglass_empty, title: 'Memuat Dashboard',
    message: 'Mengambil data paket dan pemakaian...',
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => _Card(child: Column(children: [
    Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 10),
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
    if (action != null) ...[const SizedBox(height: 12), action!],
  ]));
}
