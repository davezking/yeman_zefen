import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// A short pill of text about a score.
enum ScoreBadgeKind {
  /// A white pill: "563 pts".
  points,

  /// A dark pill with a yellow star: "New personal best".
  best,
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({
    super.key,
    required this.label,
    this.kind = ScoreBadgeKind.points,
  });

  const ScoreBadge.best({super.key, required this.label})
    : kind = ScoreBadgeKind.best;

  final String label;
  final ScoreBadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final best = kind == ScoreBadgeKind.best;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: best ? ColorTokens.surfaceDark : ColorTokens.surfaceCard,
        borderRadius: BorderRadius.circular(RadiusTokens.pill),
        boxShadow: best ? ElevationTokens.dark : ElevationTokens.chip,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.n10,
          vertical: SpacingTokens.n4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (best) ...[
              const Icon(
                Icons.star_rounded,
                size: SizeTokens.iconSmall,
                color: ColorTokens.primaryAccentOnDark,
              ),
              const SizedBox(width: SpacingTokens.n4),
            ],
            Flexible(
              child: Text(
                label,
                style: context.text.label.copyWith(
                  color: best
                      ? ColorTokens.textOnDark
                      : ColorTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
