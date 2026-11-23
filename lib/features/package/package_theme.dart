import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';

/// Palet Light Theme develop untuk halaman Paket.
///
/// Nilai di sini adalah acuan visual develop. Widget membaca warna lewat
/// [PkgPalette] agar halaman ikut Dark Mode.
abstract final class PkgColors {
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

/// Warna halaman Paket sesuai ThemeData aktif.
class PkgPalette {
  const PkgPalette({
    required this.bg,
    required this.card,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.field,
    required this.chip,
    required this.text,
    required this.muted,
    required this.avatar,
    required this.onAvatar,
    required this.danger,
    required this.dangerBg,
    required this.expiredFg,
    required this.expiredBg,
    required this.archivedFg,
    required this.archivedBg,
  });

  static PkgPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const light = PkgPalette(
    bg: PkgColors.bg,
    card: Colors.white,
    primary: PkgColors.primary,
    onPrimary: Colors.white,
    accent: PkgColors.accent,
    field: PkgColors.field,
    chip: PkgColors.chip,
    text: PkgColors.text,
    muted: PkgColors.muted,
    avatar: PkgColors.avatar,
    onAvatar: Colors.white70,
    danger: PkgColors.danger,
    dangerBg: PkgColors.dangerBg,
    expiredFg: PkgColors.expiredFg,
    expiredBg: PkgColors.expiredBg,
    archivedFg: PkgColors.archivedFg,
    archivedBg: PkgColors.archivedBg,
  );

  static const dark = PkgPalette(
    bg: AppPalette.latarGelap,
    card: AppPalette.surfaceGelap,
    primary: AppPalette.tealTerang,
    onPrimary: AppPalette.inkGelap,
    accent: Color(0xFF1B2F2B),
    field: AppPalette.surfaceTinggi,
    chip: Color(0xFF243733),
    text: AppPalette.teksGelap,
    muted: AppPalette.teksMutedGelap,
    avatar: Color(0xFF33403D),
    onAvatar: Color(0xFFD9E4E1),
    danger: AppPalette.errorGelap,
    dangerBg: Color(0xFF4A1F1C),
    expiredFg: AppPalette.errorGelap,
    expiredBg: Color(0xFF4A1F1C),
    archivedFg: Color(0xFFB6C2BF),
    archivedBg: Color(0xFF26332F),
  );

  final Color bg;
  final Color card;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color field;
  final Color chip;
  final Color text;
  final Color muted;
  final Color avatar;
  final Color onAvatar;
  final Color danger;
  final Color dangerBg;
  final Color expiredFg;
  final Color expiredBg;
  final Color archivedFg;
  final Color archivedBg;
}

/// Avatar profil di app bar.
class PkgAvatar extends StatelessWidget {
  const PkgAvatar({super.key, this.onTap, this.size = 36});

  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pal = PkgPalette.of(context);

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: pal.avatar, shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Icon(Icons.person, size: size * 0.9, color: pal.onAvatar),
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
    final pal = PkgPalette.of(context);

    return Material(
      color: pal.bg,
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
                  icon: Icon(Icons.arrow_back, color: pal.text),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: pal.text,
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

/// Kartu bersudut membulat sesuai tema.
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
    final pal = PkgPalette.of(context);

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: pal == PkgPalette.dark
            ? null
            : const [
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
    this.bg,
    this.fg,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color? bg;
  final Color? fg;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final pal = PkgPalette.of(context);
    final background = bg ?? pal.accent;
    final foreground = fg ?? pal.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
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
    final pal = PkgPalette.of(context);

    final Color bg;
    final Color fg;

    if (package.isArchived) {
      bg = pal.archivedBg;
      fg = pal.archivedFg;
    } else if (package.isExpiredAt()) {
      bg = pal.expiredBg;
      fg = pal.expiredFg;
    } else if (package.status == PackageStatus.active) {
      bg = pal.accent;
      fg = pal.primary;
    } else {
      bg = pal.chip;
      fg = pal.primary;
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
    final pal = PkgPalette.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? pal.accent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: pal.primary, size: size * 0.5),
    );
  }
}
