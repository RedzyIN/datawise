import 'package:flutter/material.dart';

import '../../models/models.dart';

class PkgColors {
  static const bg = Color(0xFFE9FAF7);
  static const primary = Color(0xFF0F766E);
  static const accent = Color(0xFF8CE8DC);
  static const field = Color(0xFFDDF6F2);
  static const chip = Color(0xFFCBEEE9);
  static const text = Color(0xFF0B2B29);
  static const muted = Color(0xFF587371);
  static const avatar = Color(0xFF9BB3B0);

  static const danger = Color(0xFFC62828);
  static const dangerBg = Color(0xFFFFDAD6);

  // Badge status paket
  static const expiredFg = Color(0xFFB3261E);
  static const expiredBg = Color(0xFFFFDAD6);
  static const archivedFg = Color(0xFF5F6B69);
  static const archivedBg = Color(0xFFE2E7E6);
}

/// Avatar profil di app bar.
class PkgAvatar extends StatelessWidget {
  const PkgAvatar({super.key, this.onTap, this.size = 36});

  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: PkgColors.avatar,
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Icon(Icons.person, size: size * 0.9, color: Colors.white70),
        ),
      ),
    );
  }
}

/// App bar halaman: back, judul, avatar profil.
class PkgAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PkgAppBar({super.key, required this.title, this.onAvatarTap});

  final String title;
  final VoidCallback? onAvatarTap;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PkgColors.bg,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back, color: PkgColors.text),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: PkgColors.text,
                    ),
                  ),
                ),
                PkgAvatar(onTap: onAvatarTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartu putih bersudut membulat.
class PkgCard extends StatelessWidget {
  const PkgCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F766E),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Pil kecil untuk label.
class PkgPill extends StatelessWidget {
  const PkgPill(
    this.label, {
    super.key,
    this.bg = PkgColors.accent,
    this.fg = PkgColors.primary,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge status paket: utama/tambahan (mint), kedaluwarsa (merah),
/// diarsipkan (abu-abu).
class PkgStatusPill extends StatelessWidget {
  const PkgStatusPill(this.package, {super.key});

  final DataPackage package;

  static String labelOf(DataPackage p) {
    if (p.isArchived) return 'Diarsipkan';
    if (p.isExpiredAt()) return 'Kedaluwarsa';
    return p.status == PackageStatus.active ? 'Paket Utama' : 'Paket Tambahan';
  }

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    if (package.isArchived) {
      bg = PkgColors.archivedBg;
      fg = PkgColors.archivedFg;
    } else if (package.isExpiredAt()) {
      bg = PkgColors.expiredBg;
      fg = PkgColors.expiredFg;
    } else if (package.status == PackageStatus.active) {
      bg = PkgColors.accent;
      fg = PkgColors.primary;
    } else {
      bg = PkgColors.chip;
      fg = PkgColors.primary;
    }

    return PkgPill(labelOf(package), bg: bg, fg: fg);
  }
}

/// Kotak ikon (persegi membulat).
class PkgIconBox extends StatelessWidget {
  const PkgIconBox(this.icon, {super.key, this.size = 44, this.bg});

  final IconData icon;
  final double size;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? PkgColors.accent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: PkgColors.primary, size: size * 0.5),
    );
  }
}
