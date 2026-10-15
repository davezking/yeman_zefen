import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'raised_surface.dart';

/// A player's colored tile on the leaderboard: a rounded square with a white
/// border and a soft highlight. There are no photos; the color is picked from
/// the brand and era colors by [colorIndex] (the player's id, say), so the
/// same player always gets the same tile.
class AvatarTile extends StatelessWidget {
  const AvatarTile({
    super.key,
    required this.colorIndex,
    required this.size,
    this.bordered = false,
  });

  final int colorIndex;
  final double size;

  /// A white ring around the tile (the podium); rows have none.
  final bool bordered;

  static const _colors = <Color>[
    ColorTokens.paletteLavender,
    ColorTokens.paletteSage,
    ColorTokens.paletteSand,
    ColorTokens.paletteCoral,
    ColorTokens.paletteWhite,
    ColorTokens.paletteSun400,
  ];

  /// The tile color for [colorIndex] (any integer).
  static Color colorFor(int colorIndex) =>
      _colors[colorIndex.abs() % _colors.length];

  @override
  Widget build(BuildContext context) {
    final ring = bordered ? SizeTokens.eraRing : 0.0;
    final tile = RaisedSurface(
      minWidth: size - 2 * ring,
      minHeight: size - 2 * ring,
      borderRadius: BorderRadius.circular(size / 3 - ring),
      color: colorFor(colorIndex),
      shadows: const [],
      inset: ElevationTokens.glossInset,
      child: const SizedBox.shrink(),
    );
    // Decorative: the name next to it is what is read out.
    return ExcludeSemantics(
      child: bordered
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size / 3),
                border: Border.all(
                  color: ColorTokens.paletteWhite,
                  width: ring,
                ),
              ),
              child: Padding(padding: EdgeInsets.all(ring), child: tile),
            )
          : tile,
    );
  }
}
