import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/token_types.dart';
import '../theme/tokens.dart';
import 'raised_surface.dart';

/// A small label in an era's color: "The '80s" on the round screen. Display only.
/// [generationId] is the catalog's era id (0 = all eras, 1-5 as in `eras.dart`).
class EraChip extends StatelessWidget {
  const EraChip({super.key, required this.label, required this.generationId});

  final String label;
  final int generationId;

  @override
  Widget build(BuildContext context) {
    return RaisedSurface(
      minHeight: SizeTokens.chipMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n12),
      color: context.game.eraColor(generationId),
      shadows: ElevationTokens.chip,
      inset: ElevationTokens.chipInset,
      child: Text(label, style: context.text.label),
    );
  }
}

/// A selectable era on the setup screen: a colored card with the era's name and,
/// optionally, its years. The selected card gets a dark ring. Pass a null
/// [onTap] (with [enabled] false) for an era the phone has no songs for.
class EraCard extends StatelessWidget {
  const EraCard({
    super.key,
    required this.label,
    required this.generationId,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final String label;

  /// Years under the name ("Before 1980"), when the era has them.
  final String? subtitle;
  final int generationId;
  final bool selected;
  final VoidCallback? onTap;

  /// False fades the card and makes it inert.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final text = context.text;
    final color = game.eraColor(generationId);
    final isAll = generationId == 0;
    final radius = BorderRadius.circular(RadiusTokens.card);
    const gap = SizeTokens.eraRingOffset;

    final card = RaisedSurface(
      onTap: enabled ? onTap : null,
      semanticLabel: subtitle == null ? label : '$label, $subtitle',
      selected: selected,
      inertButton: true,
      expand: true,
      minHeight: SizeTokens.eraCardMinHeight,
      borderRadius: radius,
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.n12,
        vertical: SpacingTokens.n6,
      ),
      color: isAll ? null : color,
      gradient: isAll
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
            )
          : null,
      shadows: ElevationTokens.chip,
      inset: ElevationTokens.chipInset,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.withWeight(text.bodySmall, FontWeight.w800),
            ),
            if (subtitle != null) Text(subtitle!, style: text.caption),
          ],
        ),
      ),
    );

    // The ring's space is always reserved, so selecting a card never shifts the grid.
    final ringed = Container(
      padding: const EdgeInsets.all(gap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          RadiusTokens.card + gap + SizeTokens.eraRing,
        ),
        border: Border.all(
          color: selected ? game.eraSelectedRing : transparentColor,
          width: SizeTokens.eraRing,
        ),
      ),
      child: card,
    );
    return enabled
        ? ringed
        : Opacity(opacity: game.answerDimOpacity, child: ringed);
  }
}
