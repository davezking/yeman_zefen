import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// The answer-window countdown: a bar that drains from right to left, with a
/// pill showing the seconds left (or "Paused" while the hint sheet or ad is up).
///
/// It draws what it is given; the round's clock decides [fraction] and [label].
/// Screen readers get [semanticLabel] ("7 seconds left") instead of the pill text.
class TimerBar extends StatelessWidget {
  const TimerBar({
    super.key,
    required this.fraction,
    this.label,
    this.semanticLabel,
  });

  /// How much of the window is left, from 1 (just started) to 0 (out of time).
  final double fraction;

  /// Text in the pill. Null hides the pill (the "next song loading" state).
  final String? label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final pillLabel = label;
    return Semantics(
      container: true,
      label: semanticLabel ?? pillLabel,
      liveRegion: false,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n6),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(RadiusTokens.progress),
                  child: ColoredBox(
                    color: game.timerTrack,
                    child: SizedBox(
                      height: SizeTokens.timerBarHeight,
                      child: FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: fraction.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              RadiusTokens.progress,
                            ),
                            gradient: LinearGradient(
                              colors: [game.timerFillStart, game.timerFillEnd],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (pillLabel != null) ...[
                const SizedBox(width: SpacingTokens.n10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: game.timerPill,
                    borderRadius: BorderRadius.circular(RadiusTokens.pill),
                    boxShadow: ElevationTokens.chip,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.n10,
                      vertical: SpacingTokens.n2,
                    ),
                    child: Text(pillLabel, style: context.text.label),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
