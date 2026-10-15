import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'edge_shadow.dart';
import 'raised_surface.dart';

/// A tappable pill for a single choice among several (the genre list). The
/// selected chip turns dark with a yellow label. [EraChip] is the display-only
/// colored label; this one is the control.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RaisedSurface(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      minHeight: SizeTokens.smallButtonMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.small),
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n14),
      gradient: selected
          ? null
          : const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
            ),
      color: selected ? ColorTokens.surfaceDark : null,
      shadows: edgeShadow(
        selected ? ColorTokens.surfaceDarkEdge : ColorTokens.surfaceCardEdge,
      ),
      child: Text(
        label,
        style: context.text.label.copyWith(
          color: selected
              ? ColorTokens.primaryAccentOnDark
              : ColorTokens.textPrimary,
        ),
      ),
    );
  }
}
