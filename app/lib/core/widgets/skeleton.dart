import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// A placeholder shape for content that is still loading: a rounded box with
/// a light sweeping across it ([MotionTokens.durationShimmer]). With reduced
/// motion it stands still. Screen readers skip it; say what is loading in a
/// status line next to it instead.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = RadiusTokens.progress,
    this.onYellow = false,
  });

  /// Null fills the width it is given.
  final double? width;
  final double height;
  final double radius;

  /// On a yellow screen (the leaderboard) the box is translucent white; on a
  /// white or cream body it is cream.
  final bool onYellow;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  AnimationController? _sweep;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sweep ??= AnimationController(
      vsync: this,
      duration: context.game.shimmerDuration,
    );
    if (context.reduceMotion) {
      // Back to the flat base color, not a highlight frozen mid-sweep.
      _sweep!.reset();
    } else if (!_sweep!.isAnimating) {
      _sweep!.repeat();
    }
  }

  @override
  void dispose() {
    _sweep?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.onYellow
        ? ColorTokens.surfaceSkeletonOnYellow
        : ColorTokens.surfaceSkeletonOnLight;
    final light = widget.onYellow
        ? ColorTokens.surfaceSkeletonOnYellowHighlight
        : ColorTokens.surfaceSkeletonOnLightHighlight;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _sweep!,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: [base, light, base],
              transform: _Slide(_sweep!.value),
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves the gradient across its box, from fully left (0) to fully right (1).
class _Slide extends GradientTransform {
  const _Slide(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// Shows [child] only once loading has taken longer than
/// [TimingTokens.skeletonDelay], so a fast load never flashes a skeleton.
class SkeletonDelay extends StatefulWidget {
  const SkeletonDelay({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonDelay> createState() => _SkeletonDelayState();
}

class _SkeletonDelayState extends State<SkeletonDelay> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(TimingTokens.skeletonDelay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _show ? widget.child : const SizedBox.shrink();
}
