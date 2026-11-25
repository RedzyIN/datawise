// PEMILIK: Anggota D (Nero). Tab 'Beranda' di /home — mengikuti frame Figma Dashboard.
//
// Pekan 1 (PRD 12.1): Dashboard dapat dirender memakai data contoh (mock) + empty state.
// Begitu pengguna login dan ada paket aktif, halaman otomatis memakai data nyata dari
// DashboardProvider (paket dari repository, hasil PlannerService, status izin).
// Halaman ini hanya MENAMPILKAN data; tidak ada rumus kuota di sini.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../shared/widgets/datawise_header.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../models/models.dart';
import '../alerts/alert_history_page.dart';
import '../alerts/alert_provider.dart';
import '../auth/auth_provider.dart';
import 'dashboard_provider.dart';

/// Frame Figma berukuran ±290 lebar; skala ini menyesuaikannya ke layar ponsel.
const double _k = 1.2;
double _u(double v) => v * _k;

const _bulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
const _hari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

String _gb(num bytes) =>
    '${(bytes / kBytesPerGB).toStringAsFixed(2).replaceAll('.', ',')} GB';
String _gbShort(num bytes) {
  final v = bytes / kBytesPerGB;
  final s = v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')} GB';
}

String _longDate(DateTime d) => '${d.day} ${_bulan[d.month - 1]}';

String _shortDate(DateTime d) =>
    '${d.day} ${_bulan[d.month - 1].substring(0, 3)}';

class _Bar {
  const _Bar(
    this.label,
    this.bytes, {
    required this.date,
    this.isToday = false,
    this.highlight = false,
  });
  final String label;
  final int bytes;
  final DateTime date;
  final bool isToday;
  final bool highlight;
}

class _Cat {
  const _Cat(this.name, this.usedBytes, this.quotaBytes);
  final String name;
  final int usedBytes, quotaBytes;
  int get remaining => quotaBytes - usedBytes < 0 ? 0 : quotaBytes - usedBytes;
}

/// Semua teks/angka yang tampil di halaman, supaya mock & data nyata memakai satu UI.
class _DashView {
  const _DashView({
    required this.userName,
    required this.operatorName,
    required this.connected,
    required this.packageTitle,
    required this.remaining,
    required this.totalText,
    required this.usedText,
    required this.usedPercent,
    required this.daysLeft,
    required this.endDate,
    required this.todayValue,
    required this.todayTarget,
    required this.todayBadge,
    required this.todayProgress,
    required this.weekValue,
    required this.weekSubtitle,
    required this.weekFooter,
    required this.weekProgress,
    required this.bars,
    required this.targetFraction,
    required this.targetText,
    required this.averageText,
    required this.tooltip,
    this.todayPercentLabel,
    this.weekPercentLabel,
    this.targetBytes,
    required this.packageForNav,
    this.categories = const [],
    this.unclassifiedBytes = 0,
    this.overQuota = false,
    this.planUnavailable = false,
    this.categoriesComplete = false,
  }) : unallocatedText = null;

  final String userName, operatorName, packageTitle;
  final bool connected;
  final String remaining, totalText, usedText;
  final int usedPercent;
  final String? daysLeft; // null = tidak ditampilkan angka hari
  final String endDate;
  final String todayValue, todayTarget, todayBadge;
  final double todayProgress;
  final String weekValue, weekSubtitle, weekFooter;
  final double weekProgress;
  final String? todayPercentLabel, weekPercentLabel;
  final List<_Bar> bars;
  final double? targetFraction;
  final int? targetBytes;
  final String targetText, averageText, tooltip;
  final DataPackage packageForNav;
  final List<_Cat> categories;
  final int unclassifiedBytes;
  final bool overQuota;
  final bool planUnavailable;
  final bool categoriesComplete;

  /// Keterangan pemakaian efektif yang belum memiliki alokasi kategori.
  final String? unallocatedText;

  /// Data contoh pekan 1 — sama dengan frame Figma.
  factory _DashView.mock() {
    final now = DateTime.now();
    final mockBytes = <int>[
      918000000,
      1162800000,
      1224000000,
      841500000,
      1071000000,
      1025100000,
      841500000,
    ];
    return _DashView(
      userName: 'Sarah',
      operatorName: 'Telkomsel',
      connected: true,
      packageTitle: 'Paket Bulanan 30 GB – Telkomsel',
      remaining: '18,40 GB',
      totalText: '30 GB',
      usedText: '11,60 GB',
      usedPercent: 39,
      daysLeft: '12 hari',
      endDate: '16 November',
      todayValue: '0,90 GB',
      todayTarget: '1,53 GB',
      todayBadge: 'Aman',
      todayProgress: .59,
      todayPercentLabel: '59%',
      weekValue: '10,71 GB',
      weekSubtitle: 'Minggu ke-3 Siklus',
      weekFooter: 'Penghematan +14%',
      weekProgress: .72,
      weekPercentLabel: '72%',
      bars: [
        for (var i = 0; i < 7; i++)
          _Bar(
            _hari[now.subtract(Duration(days: 6 - i)).weekday - 1],
            mockBytes[i],
            date: now.subtract(Duration(days: 6 - i)),
            isToday: i == 6,
            highlight: i == 2,
          ),
      ],
      targetFraction: .72,
      targetBytes: 1530000000,
      targetText: '1,53 GB',
      averageText: '1,12 GB',
      tooltip: '1,53 GB',
      categories: const [
        _Cat('Kuota Utama', 8900000000, 20 * kBytesPerGB),
        _Cat('Kuota Malam', 1200000000, 6 * kBytesPerGB),
        _Cat('Kuota Sosial', 1500000000, 4 * kBytesPerGB),
      ],
      categoriesComplete: true,
      packageForNav: DataPackage(
        id: 'preview-package',
        userId: 'preview-user',
        packageName: 'Paket Bulanan 30 GB',
        operatorName: 'Telkomsel',
        advertisedTotalQuotaBytes: 30 * kBytesPerGB,
        startDate: DateTime(now.year, now.month, 1),
        endDate: DateTime(now.year, now.month, 30),
        status: PackageStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Data nyata dari DashboardProvider (state: ready).
  factory _DashView.fromProvider(DashboardProvider d, AppUser user) {
    final pkg = d.package!;
    final plan = d.plan;
    final today = dateOnly(DateTime.now());

    final used = plan?.usedBytes ?? d.totalUsedBytes;
    final total = pkg.advertisedTotalQuotaBytes;
    final remainingBytes =
        plan?.remainingBytes ?? (total - used < 0 ? 0 : total - used);
    final ratio = plan != null
        ? (plan.usagePercent / 100).clamp(0.0, 1.0)
        : (total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0);

    // 7 hari terakhir (pemakaian efektif per tanggal dari repository).
    final days = List.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      return (date: day, bytes: d.dailyUsage[day] ?? 0);
    });
    final last7Used = days.fold<int>(0, (a, b) => a + b.bytes);
    final dailyTarget = plan?.dailyTargetBytes;
    var maxV = days
        .fold<int>(0, (a, b) => b.bytes > a ? b.bytes : a)
        .toDouble();
    if (dailyTarget != null && dailyTarget > maxV) maxV = dailyTarget;
    if (maxV <= 0) maxV = 1;

    var brightIdx = -1;
    var brightVal = 0;
    for (var i = 0; i < 6; i++) {
      if (days[i].bytes > brightVal) {
        brightVal = days[i].bytes;
        brightIdx = i;
      }
    }

    final pct = plan?.todayPercentOfTarget;
    final weeklyTarget = plan?.weeklyTargetBytes;
    final packageStart = dateOnly(pkg.startDate);
    final cycleWeek = (today.difference(packageStart).inDays ~/ 7) + 1;
    final cycleStart = packageStart.add(Duration(days: (cycleWeek - 1) * 7));
    final packageEnd = dateOnly(pkg.endDate);
    final lastCycleDay = packageEnd.isBefore(today) ? packageEnd : today;

    // Hanya pemakaian pada minggu siklus berjalan yang dihitung, sehingga
    // data minggu sebelumnya tidak ikut tercampur ke target mingguan.
    var cycleUsed = 0;
    for (final entry in d.dailyUsage.entries) {
      if (entry.key.isBefore(cycleStart)) continue;
      if (entry.key.isAfter(lastCycleDay)) continue;
      cycleUsed += entry.value;
    }

    final weekPct = (weeklyTarget != null && weeklyTarget > 0)
        ? cycleUsed / weeklyTarget * 100
        : null;

    String? daysLeft;
    if (plan != null) daysLeft = '${plan.remainingDays} hari';

    return _DashView(
      userName: _nameFrom(user),
      operatorName: pkg.operatorName ?? '',
      connected: d.hasPermission,
      packageTitle: '${pkg.packageName} – ${pkg.operatorName ?? ''}',
      remaining: _gb(remainingBytes),
      totalText: _gbShort(total),
      usedText: _gb(used),
      usedPercent: (ratio * 100).round(),
      daysLeft: daysLeft,
      endDate: _longDate(pkg.endDate),
      todayValue: _gb(plan?.todayUsedBytes ?? d.dailyUsage[today] ?? 0),
      todayTarget: dailyTarget != null ? _gb(dailyTarget) : '—',
      todayBadge: pct == null
          ? '—'
          : (pct > 100 ? 'Melebihi' : (pct >= 80 ? 'Hampir' : 'Aman')),
      todayProgress: pct != null ? (pct / 100).clamp(0.0, 1.0) : 0,
      todayPercentLabel: pct == null ? null : '${pct.toStringAsFixed(0)}%',
      weekValue: weeklyTarget != null ? _gb(weeklyTarget) : '—',
      weekSubtitle: 'Minggu ke-${cycleWeek < 1 ? 1 : cycleWeek} Siklus',
      weekFooter: 'Terpakai ${_gb(cycleUsed)}',
      weekProgress: (weeklyTarget != null && weeklyTarget > 0)
          ? (cycleUsed / weeklyTarget).clamp(0.0, 1.0)
          : 0,
      weekPercentLabel: weekPct == null
          ? null
          : '${weekPct.toStringAsFixed(0)}%',
      targetBytes: dailyTarget?.round(),
      bars: [
        for (var i = 0; i < 7; i++)
          _Bar(
            _hari[days[i].date.weekday - 1],
            days[i].bytes,
            date: days[i].date,
            isToday: i == 6,
            highlight: i == brightIdx,
          ),
      ],
      targetFraction: dailyTarget != null
          ? (dailyTarget / maxV).clamp(0.0, 1.0)
          : null,
      targetText: dailyTarget != null ? _gb(dailyTarget) : '—',
      averageText: _gb(last7Used / 7),
      tooltip: _gb(days.last.bytes),
      // Kapasitas dan pemakaian kategori berasal dari repository lewat Provider.
      // Pemakaian yang belum terklasifikasi tetap ditampilkan terpisah dan tidak
      // dibebankan ke kategori mana pun.
      categories: [
        for (final c in d.categoryUsage)
          _Cat(c.category.categoryName, c.usedBytes, c.capacityBytes),
      ],
      unclassifiedBytes: d.unclassifiedBytes,
      categoriesComplete: true,
      planUnavailable: d.planUnavailable,
      packageForNav: pkg,
      overQuota: plan != null && plan.usedBytes > plan.totalBytes,
    );
  }

  static String _nameFrom(AppUser u) {
    final displayName = u.displayName?.trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = u.email ?? '';
    final local = email.split('@').first;

    if (local.isEmpty) return 'Pengguna';

    return local[0].toUpperCase() + local.substring(1);
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  AppPageColors get pal => AppPageColors.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final uid = context.read<AuthProvider>().currentUser?.uid;
    if (uid == null) return;
    await context.read<DashboardProvider>().refresh(uid);

    // Evaluasi Smart Alerts terjadi di dalam refresh Dashboard, sehingga
    // indikator lonceng dibaca ulang setelahnya agar jumlahnya sesuai database.
    await _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    if (!mounted) return;
    final uid = context.read<AuthProvider>().currentUser?.uid;
    if (uid == null) return;
    await context.read<AlertProvider>().load(uid);
  }

  /// Membuka Notification Center, lalu memperbarui indikator lonceng.
  Future<void> _openNotificationCenter() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlertHistoryPage()),
    );

    if (!mounted) return;

    await _loadAlerts();
  }

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    final d = context.watch<DashboardProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final unreadAlerts = context.watch<AlertProvider>().unreadCount;

    Widget body;
    if (user == null) {
      // Belum ada sesi login (pekan 1 / AuthProvider belum jadi): tampilkan data contoh.
      body = _content(
        context,
        _DashView.mock(),
        d,
        preview: true,
        unreadAlerts: unreadAlerts,
      );
    } else {
      switch (d.loadState) {
        case DashboardLoad.loading:
          body = Center(child: CircularProgressIndicator(color: pal.primary));
        case DashboardLoad.error:
          body = _ErrorState(message: d.errorMessage, onRetry: _load);
        case DashboardLoad.noPackage:
          body = _emptyState(context, user, d, unreadAlerts);
        case DashboardLoad.ready:
          body = _content(
            context,
            _DashView.fromProvider(d, user),
            d,
            unreadAlerts: unreadAlerts,
          );
      }
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [pal.background, pal.backgroundEnd],
          ),
        ),
        child: SafeArea(child: body),
      ),
    );
  }

  // ------------------------------------------------------------ halaman

  Widget _content(
    BuildContext context,
    _DashView v,
    DashboardProvider d, {
    bool preview = false,
    required int unreadAlerts,
  }) {
    return RefreshIndicator(
      color: pal.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(_u(12), _u(10), _u(12), _u(16)),
        children: [
          _Header(
            v: v,
            unreadAlerts: unreadAlerts,
            onBell: _openNotificationCenter,
            onStatus: () => _showStatus(context, d, preview),
          ),
          SizedBox(height: _u(12)),
          _PackageCard(
            v: v,
            onTap: () async {
              await Navigator.pushNamed(
                context,
                Routes.packageDetail,
                arguments: v.packageForNav.id,
              );
              if (mounted) await _load();
            },
          ),
          if (!preview && !d.hasPermission) ...[
            SizedBox(height: _u(8)),
            _PermissionNotice(
              onGrant: () async {
                await d.openUsageAccessSettings();
                await d.recheckPermission();
                if (mounted) await _load();
              },
            ),
          ],
          if (!preview && v.planUnavailable) ...[
            SizedBox(height: _u(8)),
            const _PlannerNotice(),
          ],
          SizedBox(height: _u(9)),
          _DailyWeekly(v: v),
          SizedBox(height: _u(9)),
          _WeeklyChart(v: v),
          if (v.categories.isNotEmpty) ...[
            SizedBox(height: _u(9)),
            _CategoryCard(v: v),
          ],
          SizedBox(height: _u(12)),
          _PrimaryButton(
            label: 'Masukkan Pemakaian',
            onTap: () async {
              await Navigator.pushNamed(
                context,
                Routes.usageManual,
                arguments: v.packageForNav,
              );
              if (mounted) await _load();
            },
          ),
          SizedBox(height: _u(8)),
          SizedBox(
            width: double.infinity,
            child: _SecondaryButton(
              icon: Icons.apps_rounded,
              label: 'Detail Aplikasi',
              onTap: () => _showAppDetails(context, d, v.packageForNav),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    AppUser user,
    DashboardProvider d,
    int unreadAlerts,
  ) {
    final v = _DashView.mock();
    final header = _DashView(
      userName: _DashView._nameFrom(user),
      operatorName: '',
      connected: d.hasPermission,
      packageTitle: '',
      remaining: '',
      totalText: '',
      usedText: '',
      usedPercent: 0,
      daysLeft: null,
      endDate: '',
      todayValue: '',
      todayTarget: '',
      todayBadge: '',
      todayProgress: 0,
      weekValue: '',
      weekSubtitle: '',
      weekFooter: '',
      weekProgress: 0,
      bars: const [],
      targetFraction: null,
      targetText: '',
      averageText: '',
      tooltip: '',
      packageForNav: v.packageForNav,
    );
    return RefreshIndicator(
      color: pal.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(_u(12), _u(10), _u(12), _u(16)),
        children: [
          _Header(
            v: header,
            unreadAlerts: unreadAlerts,
            onBell: _openNotificationCenter,
            onStatus: () => _showStatus(context, d, false),
          ),
          if (!d.hasPermission) ...[
            SizedBox(height: _u(8)),
            _PermissionNotice(
              onGrant: () async {
                await d.openUsageAccessSettings();
                await d.recheckPermission();
                if (mounted) await _load();
              },
            ),
          ],
          SizedBox(height: _u(16)),
          Container(
            padding: EdgeInsets.all(_u(20)),
            decoration: _cardDecoration(pal, radius: 14),
            child: Column(
              children: [
                Icon(Icons.sim_card_outlined, size: _u(44), color: pal.muted),
                SizedBox(height: _u(10)),
                Text(
                  'Belum ada paket aktif',
                  style: TextStyle(
                    color: pal.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: _u(12),
                  ),
                ),
                SizedBox(height: _u(4)),
                Text(
                  'Tambahkan paket data untuk mulai memantau sisa kuota.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.muted, fontSize: _u(9.5)),
                ),
                SizedBox(height: _u(12)),
                _PrimaryButton(
                  label: 'Tambah Paket',
                  onTap: () => Navigator.pushNamed(context, Routes.packageForm),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ dialog

  // Fitur minggu 3 (Application Usage Breakdown) sengaja BELUM diaktifkan.
  // `UsageBreakdownSheet`/`UsageBreakdownProvider` tetap tersimpan dan teruji,
  // tetapi tombol ini belum membukanya karena:
  // 1. Pembacaan per aplikasi belum diverifikasi pada perangkat nyata.
  // 2. Sinkronisasi per aplikasi mengalokasikan APP_USAGE ke MAIN tanpa aturan
  //    klasifikasi, sehingga belum layak dipakai sebagai data kuota.
  // Aktifkan kembali setelah syarat di PRD/instruksi integrasi terpenuhi.
  void _showAppDetails(
    BuildContext context,
    DashboardProvider d,
    DataPackage package,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppPageColors.of(context).surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detail Aplikasi',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: pal.ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Rincian penggunaan per aplikasi akan tersedia setelah klasifikasi pemakaian terhubung.',
                style: TextStyle(color: pal.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: 'Status pemantauan',
                value: d.hasPermission ? 'Aktif' : 'Izin belum diberikan',
              ),
              const _InfoRow(
                label: 'Sumber data',
                value: 'Statistik perangkat',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatus(BuildContext context, DashboardProvider d, bool preview) {
    final granted = d.hasPermission;
    final r = d.lastReading;
    final t = d.lastUpdatedAt;
    String detail;
    if (preview) {
      detail = 'Ini data contoh. Data nyata tampil setelah login dan paket aktif tersedia.';
    } else if (!granted) {
      detail = 'Izin akses penggunaan belum diberikan. Pemakaian bisa dicatat lewat input manual.';
    } else if (r != null &&
        r.status != UsageReadStatus.ok &&
        r.message != null) {
      detail = r.message!;
    } else if (t != null) {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      detail =
          'Terakhir diperbarui ${_longDate(t)} $hh:$mm. Angka adalah estimasi, '
          'bukan catatan resmi operator.';
    } else {
      detail = 'Belum pernah diperbarui.';
    }
    if (!preview && d.dataLimit.isConfigured) {
      detail +=
          '\n\nBatas harian: ${_gb(d.dataLimit.limitBytes)} · terpakai '
          '${_gb(d.dataLimit.usedBytes)} '
          '(${d.dataLimit.percent.toStringAsFixed(0)}%).';
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          preview
              ? 'Mode contoh'
              : (granted ? 'Izin akses aktif' : 'Izin akses belum diberikan'),
        ),
        content: Text(detail),
        actions: [
          if (!preview && !granted)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await d.openUsageAccessSettings();
                await d.recheckPermission();
                if (mounted) await _load();
              },
              child: const Text('Berikan izin'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}

// ================================================================ widget

BoxDecoration _cardDecoration(AppPageColors pal, {double radius = 14}) =>
    BoxDecoration(
      color: pal.surface,
      borderRadius: BorderRadius.circular(_u(radius)),
      border: Border.all(color: pal.line),
      boxShadow: pal.isDark
          ? null
          : const [
              BoxShadow(
                color: Color(0x0F00695C),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
    );

class _Header extends StatelessWidget {
  const _Header({
    required this.v,
    required this.unreadAlerts,
    required this.onBell,
    required this.onStatus,
  });

  final _DashView v;
  final int unreadAlerts;
  final VoidCallback onBell, onStatus;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header global: ukuran, padding, dan posisi ikon mengikuti standar
        // Dashboard dan dipakai juga oleh halaman Paket serta Riwayat.
        DatawiseHeader(
          pageLabel: 'Beranda',
          unreadCount: unreadAlerts,
          onBell: onBell,
          padding: EdgeInsets.zero,
        ),
        SizedBox(height: _u(6)),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Halo, ${v.userName}!',
                    style: TextStyle(
                      color: pal.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: _u(15),
                    ),
                  ),
                  SizedBox(height: _u(4)),
                  Row(
                    children: [
                      if (v.operatorName.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: _u(7),
                            vertical: _u(3),
                          ),
                          decoration: BoxDecoration(
                            color: pal.mint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.network_cell,
                                size: _u(9),
                                color: pal.primary,
                              ),
                              SizedBox(width: _u(3)),
                              Text(
                                v.operatorName,
                                style: TextStyle(
                                  color: pal.primary,
                                  fontSize: _u(8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: _u(7)),
                      ],
                      Icon(
                        Icons.circle,
                        size: _u(5),
                        color: v.connected ? pal.primary : pal.warning,
                      ),
                      SizedBox(width: _u(4)),
                      Flexible(
                        child: Text(
                          v.connected ? 'Terhubung' : 'Izin belum diberikan',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: pal.muted, fontSize: _u(8.5)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onStatus,
              child: Container(
                width: _u(30),
                height: _u(30),
                decoration: BoxDecoration(
                  color: pal.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: pal.isDark
                          ? AppPalette.garisGelap
                          : const Color(0x1400695C),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  v.connected
                      ? Icons.router_outlined
                      : Icons.portable_wifi_off_rounded,
                  color: v.connected ? pal.primary : pal.warning,
                  size: _u(16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.v, required this.onTap});

  final _DashView v;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    final ratio = (v.usedPercent / 100).clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(_u(14)),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(_u(12)),
          decoration: _cardDecoration(pal, radius: 14).copyWith(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [pal.surfaceAccent, pal.surface, pal.surface],
              stops: const [0, .45, 1],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'KONEKSI AKTIF',
                      style: TextStyle(
                        color: pal.muted,
                        fontSize: _u(7.5),
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: _u(9),
                      vertical: _u(4),
                    ),
                    decoration: BoxDecoration(
                      color: pal.mint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${v.usedPercent}% terpakai',
                      style: TextStyle(
                        color: pal.primary,
                        fontSize: _u(8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: _u(3)),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _u(92)),
                child: Text(
                  v.packageTitle,
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: _u(12),
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: _u(6)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    v.remaining,
                    style: TextStyle(
                      color: pal.ink,
                      fontSize: _u(24),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: _u(6)),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(color: pal.muted, fontSize: _u(8.5)),
                        children: [
                          const TextSpan(text: 'tersisa dari '),
                          TextSpan(
                            text: v.totalText,
                            style: TextStyle(
                              color: pal.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: _u(7)),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: _u(6),
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: pal.line)),
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: ratio,
                          heightFactor: 1, // kunci tinggi isian = tinggi trek
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(20),
                              ),
                              gradient: LinearGradient(
                                colors: [pal.barBright, pal.primaryDeep],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: _u(5)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Terpakai: ${v.usedText}',
                    style: TextStyle(color: pal.muted, fontSize: _u(8)),
                  ),
                  Text(
                    'Sisa ${100 - v.usedPercent}%',
                    style: TextStyle(
                      color: pal.primary,
                      fontSize: _u(8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (v.overQuota)
                Padding(
                  padding: EdgeInsets.only(top: _u(4)),
                  child: Text(
                    'Pemakaian melebihi kuota paket.',
                    style: TextStyle(color: pal.danger, fontSize: _u(8)),
                  ),
                ),
              SizedBox(height: _u(8)),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: _u(8),
                  vertical: _u(7),
                ),
                decoration: BoxDecoration(
                  color: pal.mint,
                  borderRadius: BorderRadius.circular(_u(8)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_available,
                      color: pal.primary,
                      size: _u(12),
                    ),
                    SizedBox(width: _u(6)),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(color: pal.ink, fontSize: _u(8)),
                          children: [
                            if (v.daysLeft != null) ...[
                              const TextSpan(text: 'Masa aktif tersisa '),
                              TextSpan(
                                text: v.daysLeft,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(text: ' (Berakhir ${v.endDate})'),
                            ] else
                              TextSpan(text: 'Berakhir ${v.endDate}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyWeekly extends StatelessWidget {
  const _DailyWeekly({required this.v});

  final _DashView v;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _MetricCard(
              title: 'Hari Ini',
              trailing: _Badge(label: v.todayBadge, dot: true),
              value: v.todayValue,
              subtitle: Text.rich(
                TextSpan(
                  style: TextStyle(color: pal.muted, fontSize: _u(8)),
                  children: [
                    const TextSpan(text: 'Target: '),
                    TextSpan(
                      text: v.todayTarget,
                      style: TextStyle(
                        color: pal.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              progress: v.todayProgress,
              progressLabel: v.todayPercentLabel,
            ),
          ),
          SizedBox(width: _u(8)),
          Expanded(
            child: _MetricCard(
              title: 'Target Mingguan',
              trailing: Container(
                padding: EdgeInsets.all(_u(3)),
                decoration: BoxDecoration(
                  color: pal.mint,
                  borderRadius: BorderRadius.circular(_u(5)),
                ),
                child: Icon(
                  Icons.grid_view_rounded,
                  size: _u(9),
                  color: pal.primary,
                ),
              ),
              value: v.weekValue,
              subtitle: Text(
                v.weekSubtitle,
                style: TextStyle(color: pal.muted, fontSize: _u(8)),
              ),
              footer: Row(
                children: [
                  Expanded(
                    child: Text(
                      v.weekFooter,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pal.primary,
                        fontSize: _u(8),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.trending_down_rounded,
                    size: _u(10),
                    color: pal.primary,
                  ),
                ],
              ),
              progress: v.weekProgress,
              progressLabel: v.weekPercentLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.dot = false});
  final String label;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: _u(7), vertical: _u(3)),
      decoration: BoxDecoration(
        color: pal.mint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Icon(Icons.circle, size: _u(5), color: pal.primary),
            SizedBox(width: _u(3)),
          ],
          Text(
            label,
            style: TextStyle(
              color: pal.primary,
              fontSize: _u(7.5),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.trailing,
    required this.value,
    required this.subtitle,
    required this.progress,
    this.footer,
    this.progressLabel,
  });

  final String title, value;
  final Widget trailing, subtitle;
  final Widget? footer;
  final double progress;

  /// Persentase aktual terhadap target. Bisa melebihi 100% walau progress bar
  /// tetap dibatasi penuh.
  final String? progressLabel;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Container(
      padding: EdgeInsets.all(_u(10)),
      decoration: _cardDecoration(pal, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: pal.muted, fontSize: _u(8)),
                ),
              ),
              trailing,
            ],
          ),
          SizedBox(height: _u(8)),
          Text(
            value,
            style: TextStyle(
              color: pal.ink,
              fontSize: _u(15),
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: _u(2)),
          subtitle,
          if (footer != null) ...[SizedBox(height: _u(3)), footer!],
          const Spacer(),
          SizedBox(height: _u(7)),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: _u(4),
                    backgroundColor: pal.line,
                    valueColor: AlwaysStoppedAnimation(pal.primaryDeep),
                  ),
                ),
              ),
              if (progressLabel != null) ...[
                SizedBox(width: _u(6)),
                Text(
                  progressLabel!,
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: _u(7.5),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.v});

  final _DashView v;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    final plotH = _u(96);
    final maxBar = v.bars.fold<int>(
      0,
      (max, bar) => bar.bytes > max ? bar.bytes : max,
    );
    final targetBytes = v.targetBytes ?? 0;
    final peak = maxBar > targetBytes ? maxBar : targetBytes;
    final maxY = peak <= 0 ? 1.0 : peak * 1.25;
    return Container(
      padding: EdgeInsets.fromLTRB(_u(11), _u(11), _u(11), _u(9)),
      decoration: _cardDecoration(pal, radius: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pemakaian 7 Hari Terakhir',
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: _u(10),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '- - -  Target (${v.targetText})',
                style: TextStyle(color: pal.muted, fontSize: _u(7)),
              ),
            ],
          ),
          SizedBox(height: _u(1)),
          Text(
            'Rerata ${v.averageText} / hari',
            style: TextStyle(color: pal.muted, fontSize: _u(7.5)),
          ),
          SizedBox(height: _u(14)),
          SizedBox(
            height: plotH,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barGroups: [
                  for (var i = 0; i < v.bars.length; i++)
                    BarChartGroupData(
                      x: i,
                      // Nilai hari ini tetap terlihat tanpa harus disentuh.
                      showingTooltipIndicators: v.bars[i].isToday
                          ? const [0]
                          : const [],
                      barRods: [
                        BarChartRodData(
                          toY: v.bars[i].bytes.toDouble(),
                          width: _u(14),
                          color: v.bars[i].isToday
                              ? pal.primaryDeep
                              : (v.bars[i].highlight
                                    ? pal.barBright
                                    : pal.barPale),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(_u(5)),
                          ),
                        ),
                      ],
                    ),
                ],
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => pal.ink,
                    tooltipBorderRadius: BorderRadius.circular(_u(4)),
                    tooltipPadding: EdgeInsets.symmetric(
                      horizontal: _u(5),
                      vertical: _u(3),
                    ),
                    tooltipMargin: _u(6),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final bar = v.bars[group.x];

                      return BarTooltipItem(
                        '${bar.label}, ${_shortDate(bar.date)}\n'
                        '${_gb(bar.bytes)}',
                        TextStyle(
                          color: pal.surface,
                          fontSize: _u(7),
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ),
                extraLinesData: v.targetBytes == null
                    ? const ExtraLinesData()
                    : ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: v.targetBytes!.toDouble(),
                            color: pal.muted,
                            strokeWidth: 1,
                            dashArray: const [4, 3],
                          ),
                        ],
                      ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _u(18),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= v.bars.length) {
                          return const SizedBox.shrink();
                        }
                        final bar = v.bars[index];

                        return Padding(
                          padding: EdgeInsets.only(top: _u(6)),
                          child: Text(
                            bar.label,
                            style: TextStyle(
                              color: bar.isToday ? pal.ink : pal.muted,
                              fontSize: _u(7.5),
                              fontWeight: bar.isToday
                                  ? FontWeight.w800
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.v});

  final _DashView v;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_u(11)),
      decoration: _cardDecoration(pal, radius: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sisa per Kategori',
            style: TextStyle(
              color: pal.ink,
              fontSize: _u(10),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: _u(2)),
          Text(
            'Pemakaian paket ${v.usedText} dari ${v.totalText}',
            style: TextStyle(color: pal.muted, fontSize: _u(7.5)),
          ),
          SizedBox(height: _u(8)),
          for (final c in v.categories) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: TextStyle(color: pal.muted, fontSize: _u(8.5)),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: TextStyle(color: pal.muted, fontSize: _u(8)),
                    children: [
                      TextSpan(
                        text: _gb(c.remaining),
                        style: TextStyle(
                          color: pal.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(text: ' tersisa dari ${_gbShort(c.quotaBytes)}'),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: _u(4)),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(
                value: c.quotaBytes <= 0
                    ? 0
                    : (c.usedBytes / c.quotaBytes).clamp(0.0, 1.0),
                minHeight: _u(4),
                backgroundColor: pal.line,
                valueColor: AlwaysStoppedAnimation(pal.primaryDeep),
              ),
            ),
            SizedBox(height: _u(3)),
            Text(
              'Terpakai ${_gb(c.usedBytes)} dari ${_gbShort(c.quotaBytes)}',
              style: TextStyle(color: pal.muted, fontSize: _u(7.5)),
            ),
            SizedBox(height: _u(8)),
          ],
          if (v.unclassifiedBytes > 0) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Belum terklasifikasi',
                    style: TextStyle(color: pal.muted, fontSize: _u(8.5)),
                  ),
                ),
                Text(
                  _gb(v.unclassifiedBytes),
                  style: TextStyle(
                    color: pal.ink,
                    fontSize: _u(8),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            SizedBox(height: _u(2)),
            Text(
              'Pemakaian ini belum memiliki alokasi kategori sehingga tidak '
              'dibebankan ke kategori mana pun, tetapi tetap dihitung pada '
              'pemakaian paket di atas.',
              style: TextStyle(color: pal.muted, fontSize: _u(7.5)),
            ),
            SizedBox(height: _u(8)),
          ],
          if (!v.categoriesComplete)
            Padding(
              padding: EdgeInsets.only(top: _u(2)),
              child: Text(
                'Rincian kategori tambahan belum tersedia dari data Dashboard saat ini.',
                style: TextStyle(color: pal.muted, fontSize: _u(7.5)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Container(
      padding: EdgeInsets.all(_u(10)),
      decoration: BoxDecoration(
        color: pal.noticeBg,
        borderRadius: BorderRadius.circular(_u(10)),
        border: Border.all(color: pal.noticeBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: pal.warning, size: _u(16)),
          SizedBox(width: _u(7)),
          Expanded(
            child: Text(
              'Izin akses penggunaan belum diberikan. Data otomatis belum dapat dibaca.',
              style: TextStyle(color: pal.ink, fontSize: _u(8)),
            ),
          ),
          TextButton(
            onPressed: onGrant,
            child: Text('Beri izin', style: TextStyle(fontSize: _u(8))),
          ),
        ],
      ),
    );
  }
}

class _PlannerNotice extends StatelessWidget {
  const _PlannerNotice();

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_u(9)),
      decoration: BoxDecoration(
        color: pal.mint,
        borderRadius: BorderRadius.circular(_u(9)),
      ),
      child: Text(
        'Target harian dan mingguan belum tersedia. Ringkasan pemakaian dan grafik tetap ditampilkan.',
        style: TextStyle(color: pal.muted, fontSize: _u(8)),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return SizedBox(
      width: double.infinity,
      height: _u(38),
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.add_circle_outline, size: _u(14)),
        label: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: _u(10.5)),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: pal.primaryDeep,
          foregroundColor: pal.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_u(10)),
          ),
          elevation: 2,
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return SizedBox(
      height: _u(32),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: _u(11)),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(fontSize: _u(8), fontWeight: FontWeight.w700),
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: pal.primary,
          backgroundColor: pal.mint,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_u(8)),
          ),
          padding: EdgeInsets.symmetric(horizontal: _u(6)),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: pal.muted),
            const SizedBox(height: 12),
            Text(
              message ?? 'Gagal memuat Beranda.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: pal.primaryDeep),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: pal.muted, fontSize: 11),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: pal.ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
