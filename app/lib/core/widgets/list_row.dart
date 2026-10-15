import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'raised_surface.dart';

/// A tappable row: a colored icon tile, a title, an optional second line and a
/// chevron. [dark] is the inverted version used for the Leaderboard entry on Home.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.iconColor = ColorTokens.paletteSun400,
    this.dark = false,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;

  /// Fill of the square behind the icon: a brand or era color.
  final Color iconColor;
  final VoidCallback? onTap;
  final bool dark;

  /// Replaces the chevron.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final ink = dark ? ColorTokens.textOnDark : ColorTokens.textPrimary;
    final muted = dark
        ? ColorTokens.textOnDarkMuted
        : ColorTokens.textSecondary;
    return RaisedSurface(
      onTap: onTap,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      expand: true,
      minHeight: SizeTokens.listRowMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.large),
      padding: const EdgeInsetsDirectional.fromSTEB(
        SpacingTokens.n10,
        SpacingTokens.n8,
        SpacingTokens.n14,
        SpacingTokens.n8,
      ),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const [ColorTokens.paletteSlate, ColorTokens.surfaceDark]
            : const [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
      ),
      shadows: dark ? ElevationTokens.dark : ElevationTokens.row,
      child: Row(
        children: [
          IconTile(icon: icon, color: iconColor),
          const SizedBox(width: SpacingTokens.n12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.bodyLarge.copyWith(color: ink)),
                if (subtitle != null)
                  Text(subtitle!, style: text.caption.copyWith(color: muted)),
              ],
            ),
          ),
          const SizedBox(width: SpacingTokens.n8),
          trailing ??
              Icon(
                Icons.chevron_right_rounded,
                size: SizeTokens.iconLarge,
                color: ink,
              ),
        ],
      ),
    );
  }
}

/// The glossy colored square that holds an icon in rows and pack cards.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.color, this.icon});

  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return RaisedSurface(
      minWidth: SizeTokens.iconTile,
      minHeight: SizeTokens.iconTile,
      borderRadius: BorderRadius.circular(RadiusTokens.small),
      color: color,
      shadows: const [],
      inset: ElevationTokens.glossInset,
      child: icon == null
          ? const SizedBox.shrink()
          : Icon(
              icon,
              size: SizeTokens.iconLarge,
              color: ColorTokens.textPrimary,
            ),
    );
  }
}
