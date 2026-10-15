import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// A dark strip with an icon and one or two lines, announced when it appears
/// (the offline banner on Home). It informs; it is not tappable.
class DarkBanner extends StatelessWidget {
  const DarkBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ColorTokens.surfaceDark,
            borderRadius: BorderRadius.circular(RadiusTokens.small),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.n12,
              vertical: SpacingTokens.n8,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: SizeTokens.iconLarge,
                  color: ColorTokens.primaryAccentOnDark,
                ),
                const SizedBox(width: SpacingTokens.n8),
                Expanded(
                  child: Text(
                    text,
                    style: AppTextStyles.withWeight(
                      context.text.caption,
                      FontWeight.w600,
                    ).copyWith(color: ColorTokens.textOnDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small translucent tile on the yellow hero: a label over a value. Home
/// shows "Your best" and "Play button starts" in two of these.
class StatTile extends StatelessWidget {
  /// A big number in Poppins (the best score).
  const StatTile.number({
    super.key,
    required this.label,
    required String this.number,
  }) : text = null;

  /// A line of words (what Play will start, or "Play a game to set your first best score.").
  const StatTile.text({
    super.key,
    required this.label,
    required String this.text,
  }) : number = null;

  final String label;
  final String? number;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final styles = context.text;
    final value = number != null
        ? Text(
            number!,
            style: AppTextStyles.latin(styles.title)
                .copyWith(height: TypeTokens.lineHeightLatin),
          )
        : Text(text!, style: styles.bodySmall);
    return Semantics(
      container: true,
      label: '$label, ${number ?? text}',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ColorTokens.surfaceCardOnYellow,
            borderRadius: BorderRadius.circular(RadiusTokens.card),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.n14,
              vertical: SpacingTokens.n10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: styles.caption.copyWith(
                    color: ColorTokens.textSecondary,
                  ),
                ),
                value,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
