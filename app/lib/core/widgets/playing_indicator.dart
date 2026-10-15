import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// The cassette on the round screen. While a clip plays ([playing]) its two
/// reels turn; they stop when it ends. With reduced motion on, they never turn
/// and the cassette is a still picture.
///
/// Design note: the approved artifact draws plain round reels, whose rotation
/// cannot be seen. These have six small teeth so the turning is visible.
class PlayingIndicator extends StatefulWidget {
  const PlayingIndicator({
    super.key,
    required this.playing,
    this.semanticLabel,
  });

  final bool playing;

  /// Spoken while playing ("Clip playing"). Not announced when stopped.
  final String? semanticLabel;

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  AnimationController? _spin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spin ??= AnimationController(
      vsync: this,
      duration: context.game.reelSpinDuration,
    );
    _sync();
  }

  @override
  void didUpdateWidget(PlayingIndicator old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final spin = _spin!;
    final shouldSpin = widget.playing && !context.reduceMotion;
    if (shouldSpin && !spin.isAnimating) {
      spin.repeat();
    } else if (!shouldSpin && spin.isAnimating) {
      spin.stop();
    }
  }

  @override
  void dispose() {
    _spin?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spin = _spin;
    Widget reel() => spin == null
        ? const _Reel()
        : RotationTransition(turns: spin, child: const _Reel());

    final body = DecoratedBox(
      // The translucent ring around the cassette.
      decoration: BoxDecoration(
        color: ColorTokens.cassetteRim,
        borderRadius: BorderRadius.circular(
          RadiusTokens.card + SizeTokens.cassetteRim,
        ),
        boxShadow: ElevationTokens.cassette,
      ),
      child: Padding(
        padding: const EdgeInsets.all(SizeTokens.cassetteRim),
        child: SizedBox(
          width: SizeTokens.cassetteWidth,
          height: SizeTokens.cassetteHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RadiusTokens.card),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [ColorTokens.cassetteBody, ColorTokens.paletteInk],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SizeTokens.cassettePadding,
                SizeTokens.cassettePadding,
                SizeTokens.cassettePadding,
                0,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(RadiusTokens.pill),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            ColorTokens.cassetteLabel,
                            ColorTokens.cassetteLabelEnd,
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpacingTokens.n8,
                          vertical: SpacingTokens.n4,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  RadiusTokens.progress,
                                ),
                                gradient: const LinearGradient(
                                  colors: [
                                    ColorTokens.cassetteStripe,
                                    ColorTokens.paletteSun200,
                                  ],
                                ),
                              ),
                              child: const SizedBox(
                                height: SizeTokens.cassetteStripeHeight,
                                width: double.infinity,
                              ),
                            ),
                            const SizedBox(height: SpacingTokens.n6),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: ColorTokens.cassetteWindow,
                                borderRadius: BorderRadius.circular(
                                  SizeTokens.cassetteWindowHeight / 2,
                                ),
                              ),
                              child: SizedBox(
                                height: SizeTokens.cassetteWindowHeight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: SpacingTokens.n6,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      reel(),
                                      const Expanded(child: _Tape()),
                                      reel(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: SizeTokens.cassetteGap),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SizeTokens.cassetteTabInset,
                    ),
                    child: const _Tape(
                      height: SizeTokens.cassetteTabHeight,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(RadiusTokens.pill),
                      ),
                      margin: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final label = widget.semanticLabel;
    return Semantics(
      label: widget.playing ? label : null,
      container: label != null,
      child: ExcludeSemantics(child: body),
    );
  }
}

class _Tape extends StatelessWidget {
  const _Tape({
    this.height = SizeTokens.cassetteTapeHeight,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(RadiusTokens.progress),
    ),
    this.margin = SpacingTokens.n6,
  });

  final double height;
  final BorderRadius borderRadius;
  final double margin;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    margin: EdgeInsets.symmetric(horizontal: margin),
    decoration: BoxDecoration(
      borderRadius: borderRadius,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ColorTokens.cassetteTape, ColorTokens.cassetteTapeEnd],
      ),
    ),
  );
}

/// One reel: a cream ring, a yellow hub and six teeth.
class _Reel extends StatelessWidget {
  const _Reel();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: SizeTokens.cassetteReel,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: ColorTokens.cassetteReel,
        ),
        child: CustomPaint(painter: _TeethPainter()),
      ),
    );
  }
}

class _TeethPainter extends CustomPainter {
  const _TeethPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()..color = ColorTokens.cassetteReelHub;
    final r = size.width / 2;
    canvas.drawCircle(c, r / 3, paint);
    final tooth = Paint()
      ..color = ColorTokens.cassetteReelHub
      ..strokeWidth = r / 5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r * 0.55), c + dir * (r * 0.8), tooth);
    }
  }

  @override
  bool shouldRepaint(_TeethPainter old) => false;
}
