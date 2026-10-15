import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'raised_surface.dart';

/// A large option card on Mode select: a colored icon tile, the mode's name
/// with an optional tag ("+25%", "Bonus"), and a description. The selected
/// card turns dark.
class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.selected,
    required this.onTap,
    this.tag,
  });

  final String title;
  final String description;
  final IconData icon;

  /// Fill of the square behind the icon: the mode's color.
  final Color iconColor;
  final bool selected;
  final VoidCallback? onTap;

  /// A small yellow label next to the name.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final ink = selected ? ColorTokens.textOnDark : ColorTokens.textPrimary;
    return RaisedSurface(
      onTap: onTap,
      selected: selected,
      semanticLabel: [title, ?tag, description].join(', '),
      expand: true,
      borderRadius: BorderRadius.circular(RadiusTokens.modeCard),
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.n16,
        vertical: SpacingTokens.n14,
      ),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: selected
            ? const [ColorTokens.paletteSlate, ColorTokens.surfaceDark]
            : const [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
      ),
      shadows: selected ? ElevationTokens.dark : ElevationTokens.answer,
      child: Row(
        children: [
          RaisedSurface(
            minWidth: SizeTokens.modeIconTile,
            minHeight: SizeTokens.modeIconTile,
            borderRadius: BorderRadius.circular(RadiusTokens.modeIcon),
            color: iconColor,
            shadows: const [],
            inset: ElevationTokens.glossInset,
            child: Icon(
              icon,
              size: SizeTokens.iconLarge,
              color: ColorTokens.textPrimary,
            ),
          ),
          const SizedBox(width: SpacingTokens.n14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: SpacingTokens.n8,
                  runSpacing: SpacingTokens.n2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.withWeight(
                        text.bodyLarge,
                        FontWeight.w800,
                      ).copyWith(color: ink),
                    ),
                    if (tag != null) _Tag(tag!),
                  ],
                ),
                Text(
                  description,
                  style: AppTextStyles.withWeight(
                    text.label,
                    FontWeight.w400,
                  ).copyWith(color: ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorTokens.paletteSun400,
        borderRadius: BorderRadius.circular(SpacingTokens.n8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.n8,
          vertical: SpacingTokens.n2,
        ),
        child: Text(
          label,
          style: AppTextStyles.withWeight(
            context.text.caption,
            FontWeight.w800,
          ).copyWith(color: ColorTokens.textPrimary),
        ),
      ),
    );
  }
}
