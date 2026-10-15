import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/tokens.dart';
import 'raised_surface.dart';

/// The wordmark የማን ዘፈን: one Fidel per colored tile, with a gap between the
/// two words. It reads as [semanticLabel] (the app's name) for screen readers.
class LogoTiles extends StatelessWidget {
  const LogoTiles({
    super.key,
    required this.semanticLabel,
    this.tileSize = SizeTokens.logoTile,
  });

  final String semanticLabel;
  final double tileSize;

  // Tile fill per Fidel: white, sage, white | coral, white, sand
  // (tokens.json color.logoTiles).
  static const _tiles = <(String, Color)>[
    ('የ', ColorTokens.paletteWhite),
    ('ማ', ColorTokens.paletteSage),
    ('ን', ColorTokens.paletteWhite),
    ('ዘ', ColorTokens.paletteCoral),
    ('ፈ', ColorTokens.paletteWhite),
    ('ን', ColorTokens.paletteSand),
  ];

  @override
  Widget build(BuildContext context) {
    final glyph = AppTextStyles.withWeight(
      AppTextStyles.forLocale(const Locale('am')).label,
      FontWeight.w800,
    ).copyWith(fontSize: tileSize / 2);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _tiles.length; i++) ...[
              if (i == 3) const SizedBox(width: SpacingTokens.n6),
              if (i > 0 && i != 3) const SizedBox(width: SpacingTokens.n4),
              RaisedSurface(
                minWidth: tileSize,
                minHeight: tileSize,
                borderRadius: BorderRadius.circular(RadiusTokens.pill),
                color: _tiles[i].$2,
                shadows: ElevationTokens.chip,
                inset: ElevationTokens.chipInset,
                child: Text(_tiles[i].$1, style: glyph),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
