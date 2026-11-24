// Halaman riwayat Smart Alerts.
//
// Hanya membaca data dari AlertProvider; tidak mengakses repository SQLite
// secara langsung.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../auth/auth_provider.dart';
import 'alert_provider.dart';

class AlertHistoryPage extends StatefulWidget {
  const AlertHistoryPage({super.key});

  @override
  State<AlertHistoryPage> createState() => _AlertHistoryPageState();
}

class _AlertHistoryPageState extends State<AlertHistoryPage> {
  AppPageColors get pal => AppPageColors.of(context);

  String? _requestedUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final uid = context.watch<AuthProvider>().currentUser?.uid;

    if (uid == null || uid == _requestedUid) return;

    _requestedUid = uid;

    Future.microtask(() async {
      if (!mounted) return;
      await context.read<AlertProvider>().load(uid);
    });
  }

  String _formatTime(DateTime time) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];

    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return '${time.day} ${months[time.month - 1]} ${time.year} • '
        '$hour:$minute';
  }

  String _typeLabel(String alertType) {
    return switch (alertTypeOrNull(alertType)) {
      AlertType.daily80 => 'Pemakaian target harian 80%',
      AlertType.daily100 => 'Target harian tercapai',
      AlertType.dailyOver => 'Target harian terlampaui',
      AlertType.quota20 => 'Sisa kuota utama menipis',
      AlertType.expiring1d => 'Paket berakhir besok',
      null => 'Notifikasi DATAWISE',
    };
  }

  IconData _typeIcon(String alertType) {
    return switch (alertTypeOrNull(alertType)) {
      AlertType.daily80 => Icons.speed_rounded,
      AlertType.daily100 => Icons.flag_rounded,
      AlertType.dailyOver => Icons.trending_up_rounded,
      AlertType.quota20 => Icons.battery_alert_rounded,
      AlertType.expiring1d => Icons.event_busy_rounded,
      null => Icons.notifications_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<AlertProvider>();

    final uid = auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: pal.background,
      appBar: AppBar(
        backgroundColor: pal.background,
        foregroundColor: pal.ink,
        title: const Text('Riwayat Notifikasi'),
        actions: [
          if (provider.unreadCount > 0)
            TextButton(
              onPressed: () async {
                await context.read<AlertProvider>().markAllRead();
              },
              child: const Text('Tandai semua'),
            ),
        ],
      ),
      body: _buildBody(uid, provider),
    );
  }

  Widget _buildBody(String? uid, AlertProvider provider) {
    if (uid == null) {
      return _statusView(
        Text(
          'Silakan masuk untuk melihat riwayat notifikasi.',
          textAlign: TextAlign.center,
          style: TextStyle(color: pal.muted),
        ),
      );
    }

    if (provider.loadState == AlertHistoryLoad.loading ||
        provider.loadState == AlertHistoryLoad.idle) {
      return _statusView(CircularProgressIndicator(color: pal.primary));
    }

    if (provider.loadState == AlertHistoryLoad.error) {
      return _statusView(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Gagal memuat riwayat notifikasi.',
              style: TextStyle(color: pal.ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              provider.errorMessage ?? '-',
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.muted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.read<AlertProvider>().load(uid),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }

    if (provider.isEmpty) {
      return _statusView(_buildEmptyState());
    }

    return RefreshIndicator(
      color: pal.primary,
      onRefresh: () => context.read<AlertProvider>().refresh(uid),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            '${provider.entries.length} notifikasi • '
            '${provider.unreadCount} belum dibaca',
            style: TextStyle(fontSize: 13, color: pal.muted),
          ),
          const SizedBox(height: 16),
          ...provider.entries.map(_buildAlertCard),
        ],
      ),
    );
  }

  Widget _statusView(Widget child) {
    return Center(
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: pal.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 38,
              color: pal.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Belum Ada Riwayat Notifikasi',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: pal.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Peringatan target harian, sisa kuota, dan masa aktif paket akan '
            'muncul di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: pal.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(AlertHistoryEntry entry) {
    final alert = entry.alert;
    final unread = !alert.isRead;

    return InkWell(
      onTap: unread
          ? () => context.read<AlertProvider>().markRead(alert.id ?? '')
          : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: unread ? pal.primary.withValues(alpha: 0.45) : pal.line,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: pal.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _typeIcon(alert.alertType),
                    size: 20,
                    color: pal.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _typeLabel(alert.alertType),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: pal.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.packageName ?? 'Paket tidak ditemukan',
                        style: TextStyle(fontSize: 12, color: pal.muted),
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pal.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Belum dibaca',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: pal.primary,
                      ),
                    ),
                  )
                else
                  Text(
                    'Sudah dibaca',
                    style: TextStyle(fontSize: 10, color: pal.muted),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              alert.message,
              style: TextStyle(fontSize: 13, height: 1.4, color: pal.ink),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: pal.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formatTime(alert.triggeredAt),
                    style: TextStyle(fontSize: 11, color: pal.muted),
                  ),
                ),
                if (alert.observedBytes != null)
                  Text(
                    'Tercatat ${formatBytes(alert.observedBytes!)}',
                    style: TextStyle(fontSize: 11, color: pal.muted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
