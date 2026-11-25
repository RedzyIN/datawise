// Header global DATAWISE.
//
// Satu komponen untuk Dashboard, Paket, Riwayat, dan Notification Center agar
// tinggi, padding, ukuran teks, serta posisi ikon konsisten. Ukuran mengikuti
// skala frame Dashboard (1.2x) yang sudah menjadi acuan desain.
import 'package:flutter/material.dart';

import '../../core/theme.dart';

const double _kHeaderScale = 1.2;

double _headerUnit(double value) => value * _kHeaderScale;

class DatawiseHeader extends StatelessWidget {
  const DatawiseHeader({
    super.key,
    required this.pageLabel,
    this.onBell,
    this.unreadCount = 0,
    this.onBack,
    this.onAvatarTap,
    this.padding,
  });

  final String pageLabel;

  /// Bila null, ikon lonceng tidak ditampilkan.
  final VoidCallback? onBell;

  /// Jumlah alert yang belum dibaca. Angka ini berasal dari database.
  final int unreadCount;

  /// Bila diisi, tombol kembali ditampilkan (halaman yang di-push).
  final VoidCallback? onBack;

  final VoidCallback? onAvatarTap;

  /// Padding luar. Default mengikuti halaman yang memiliki header tetap.
  final EdgeInsetsGeometry? padding;

  EdgeInsetsGeometry get _effectivePadding =>
      padding ??
      EdgeInsets.fromLTRB(
        _headerUnit(12),
        _headerUnit(10),
        _headerUnit(12),
        _headerUnit(5),
      );

  @override
  Widget build(BuildContext context) {
    final pal = AppPageColors.of(context);

    return Padding(
      padding: _effectivePadding,
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              onPressed: onBack,
              tooltip: 'Kembali',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.all(_headerUnit(4)),
              constraints: const BoxConstraints(),
              icon: Icon(
                Icons.arrow_back_rounded,
                color: pal.ink,
                size: _headerUnit(15),
              ),
            ),
            SizedBox(width: _headerUnit(2)),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DATAWISE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pal.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: _headerUnit(11),
                    letterSpacing: .4,
                  ),
                ),
                Text(
                  pageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.muted, fontSize: _headerUnit(8)),
                ),
              ],
            ),
          ),
          if (onBell != null)
            _BellButton(
              unreadCount: unreadCount,
              onTap: onBell!,
              iconColor: pal.ink,
              badgeColor: pal.danger,
              surfaceColor: pal.surface,
            ),
          SizedBox(width: _headerUnit(4)),
          _HeaderAvatar(
            color: pal.avatarBg,
            iconColor: pal.ink,
            onTap: onAvatarTap,
          ),
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({
    required this.unreadCount,
    required this.onTap,
    required this.iconColor,
    required this.badgeColor,
    required this.surfaceColor,
  });

  final int unreadCount;
  final VoidCallback onTap;
  final Color iconColor;
  final Color badgeColor;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: unreadCount > 0
          ? 'Notifikasi, $unreadCount belum dibaca'
          : 'Notifikasi, tidak ada yang belum dibaca',
      child: GestureDetector(
        key: const ValueKey('header-bell'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.all(_headerUnit(6)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.notifications_none_rounded,
                color: iconColor,
                size: _headerUnit(17),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -_headerUnit(5),
                  top: -_headerUnit(4),
                  child: Container(
                    constraints: BoxConstraints(minWidth: _headerUnit(13)),
                    height: _headerUnit(13),
                    padding: EdgeInsets.symmetric(horizontal: _headerUnit(2.5)),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: surfaceColor, width: 1),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      key: const ValueKey('header-bell-badge'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _headerUnit(7),
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({
    required this.color,
    required this.iconColor,
    this.onTap,
  });

  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _headerUnit(26),
        height: _headerUnit(26),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(Icons.person, color: iconColor, size: _headerUnit(18)),
      ),
    );
  }
}
