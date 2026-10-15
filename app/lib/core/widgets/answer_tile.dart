import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'raised_surface.dart';

/// What an answer tile shows.
enum AnswerState {
  /// Waiting to be picked.
  idle,

  /// The player's pick, before the answer is known.
  selected,

  /// The right answer, revealed. Teal, with a check and a word.
  correct,

  /// The player's wrong pick, revealed. Red, with an X and a word.
  wrong,

  /// Not picked while the answer is shown: faded.
  disabled,

  /// Taken away by the hint: nearly invisible, not tappable, not announced.
  removed,
}

/// One of the four answers in a round, in the 2 x 2 grid.
///
/// Only an [AnswerState.idle] tile with an [onTap] can be pressed. Correct and
/// wrong are never shown by color alone: they carry an icon and [stateLabel]
/// ("Correct", "Your pick"), and the reveal plays a short pop unless the system
/// asked for reduced motion.
class AnswerTile extends StatefulWidget {
  const AnswerTile({
    super.key,
    required this.text,
    this.state = AnswerState.idle,
    this.onTap,
    this.stateLabel,
    this.semanticLabel,
  });

  /// The answer, as the player reads it (a song or an artist).
  final String text;
  final AnswerState state;

  /// Called when an idle tile is tapped.
  final VoidCallback? onTap;

  /// The word next to the icon for [AnswerState.correct] and [AnswerState.wrong].
  final String? stateLabel;

  /// Spoken instead of [text]: "Answer 2: Aster Aweke". The state label is appended.
  final String? semanticLabel;

  @override
  State<AnswerTile> createState() => _AnswerTileState();
}

class _AnswerTileState extends State<AnswerTile>
    with SingleTickerProviderStateMixin {
  AnimationController? _pop;

  /// Built once with the controller. Building it in [build] would add a status
  /// listener to the controller on every rebuild, and the round rebuilds often.
  Animation<double>? _popScale;
  CurvedAnimation? _popCurve;

  static bool _reveals(AnswerState s) =>
      s == AnswerState.correct || s == AnswerState.wrong;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pop == null) {
      final game = context.game;
      final controller = AnimationController(
        vsync: this,
        duration: game.popDuration,
      );
      _pop = controller;
      _popCurve = CurvedAnimation(
        parent: controller,
        curve: game.standardCurve,
      );
      _popScale = _buildPop(_popCurve!);
    }
    if (_reveals(widget.state) &&
        !context.reduceMotion &&
        _pop!.status == AnimationStatus.dismissed) {
      _pop!.forward();
    }
  }

  @override
  void didUpdateWidget(AnswerTile old) {
    super.didUpdateWidget(old);
    if (_reveals(widget.state) &&
        !_reveals(old.state) &&
        !context.reduceMotion) {
      _pop!.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _popCurve?.dispose();
    _pop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final text = context.text;
    final state = widget.state;

    final reveal = switch (state) {
      AnswerState.correct => game.correct,
      AnswerState.wrong => game.wrong,
      _ => null,
    };

    final Gradient gradient;
    final List<BoxShadow> shadows;
    final Color ink;
    switch (state) {
      case AnswerState.correct:
        gradient = _vertical(reveal!.top, reveal.bottom);
        shadows = ElevationTokens.answerCorrect;
        ink = ColorTokens.textOnAnswerState;
      case AnswerState.wrong:
        gradient = _vertical(reveal!.top, reveal.bottom);
        shadows = ElevationTokens.answerWrong;
        ink = ColorTokens.textOnAnswerState;
      case AnswerState.selected:
        gradient = _vertical(ColorTokens.paletteSlate, ColorTokens.surfaceDark);
        shadows = ElevationTokens.dark;
        ink = ColorTokens.textOnDark;
      case AnswerState.idle || AnswerState.disabled:
        gradient = _vertical(
          ColorTokens.surfaceCard,
          ColorTokens.surfaceCardEnd,
        );
        shadows = ElevationTokens.answer;
        ink = ColorTokens.textPrimary;
      case AnswerState.removed:
        gradient = _vertical(
          ColorTokens.surfaceCard,
          ColorTokens.surfaceCardEnd,
        );
        shadows = const [];
        ink = ColorTokens.textPrimary;
    }

    final opacity = switch (state) {
      AnswerState.disabled => game.answerDimOpacity,
      AnswerState.removed => game.answerRemovedOpacity,
      _ => 1.0,
    };

    final tappable = state == AnswerState.idle && widget.onTap != null;
    final mark = _mark(state);
    final label = widget.stateLabel;

    Widget tile = RaisedSurface(
      onTap: tappable ? widget.onTap : null,
      semanticLabel: widget.semanticLabel == null
          ? null
          : (mark == null || label == null
                ? widget.semanticLabel
                : '${widget.semanticLabel}, $label'),
      expand: true,
      minHeight: SizeTokens.answerTileMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.large),
      padding: const EdgeInsets.symmetric(
        vertical: SpacingTokens.n8,
        horizontal: SpacingTokens.n10,
      ),
      gradient: gradient,
      shadows: shadows,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            textAlign: TextAlign.center,
            style: text.bodyLarge.copyWith(color: ink),
          ),
          if (mark != null) ...[
            const SizedBox(height: SpacingTokens.n2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(mark, size: SizeTokens.iconSmall, color: ink),
                if (label != null) ...[
                  const SizedBox(width: SpacingTokens.n4),
                  Flexible(
                    child: Text(
                      label,
                      style: AppTextStyles.withWeight(
                        text.caption,
                        FontWeight.w700,
                      ).copyWith(color: ink),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    // A tile that is not the one in play is faded, and if it is only decoration
    // (state shown, nothing to tap) it should not read like a button either.
    if (state == AnswerState.removed) {
      tile = ExcludeSemantics(
        child: IgnorePointer(
          child: Opacity(opacity: opacity, child: tile),
        ),
      );
    } else if (opacity != 1.0) {
      tile = Opacity(opacity: opacity, child: tile);
    }

    final popScale = _popScale;
    if (popScale != null && _reveals(state) && !context.reduceMotion) {
      tile = ScaleTransition(scale: popScale, child: tile);
    }
    return tile;
  }

  /// Scale 0.96 -> 1.03 (at 60%) -> 1, as in the design.
  static Animation<double> _buildPop(CurvedAnimation curve) =>
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.03), weight: 60),
        TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 40),
      ]).animate(curve);

  static LinearGradient _vertical(Color top, Color bottom) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [top, bottom],
  );

  /// The icon that says right or wrong without relying on color.
  static IconData? _mark(AnswerState state) => switch (state) {
    AnswerState.correct => Icons.check_rounded,
    AnswerState.wrong => Icons.close_rounded,
    _ => null,
  };
}
