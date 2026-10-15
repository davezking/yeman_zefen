import 'package:flutter/widgets.dart';

import '../theme/theme_context.dart';

/// Shows a whole number that counts up (or down) to a new [value] whenever it
/// changes: the running score on the round screen, the total on Results. With
/// reduced motion on it jumps straight to the new value instead.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.builder,
    this.fromZero = false,
  });

  final int value;

  /// Count up from 0 the first time it appears (the total on Results), not
  /// only when the value later changes.
  final bool fromZero;

  /// Builds the text for the number being shown right now.
  final Widget Function(BuildContext context, int shown) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: fromZero ? 0 : null, end: value),
      duration: context.reduceMotion ? Duration.zero : context.game.popDuration,
      curve: context.game.standardCurve,
      builder: (context, shown, _) => builder(context, shown),
    );
  }
}
