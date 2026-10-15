import 'package:flutter/material.dart';

import 'tokens.dart';

/// Fill, press edge and glow for an answer revealed as right or wrong.
@immutable
class RevealColors {
  const RevealColors({
    required this.top,
    required this.bottom,
    required this.edge,
    required this.glow,
    required this.heading,
  });

  /// Top and bottom of the tile gradient.
  final Color top;
  final Color bottom;

  /// The solid shadow under the tile.
  final Color edge;
  final Color glow;

  /// The "Correct +143" / "Not this one" heading on white.
  final Color heading;
}

/// The game's own colors and motion, read from the theme so a future dark
/// theme can swap them. Values come from [ColorTokens] and [MotionTokens].
///
/// Correct and wrong are always paired with an icon and a word as well as
/// color; the widgets that use these colors add both.
@immutable
class GameTokens extends ThemeExtension<GameTokens> {
  const GameTokens({
    required this.correct,
    required this.wrong,
    required this.timerTrack,
    required this.timerFillStart,
    required this.timerFillEnd,
    required this.timerPill,
    required this.eraColors,
    required this.eraSelectedRing,
    required this.answerDimOpacity,
    required this.answerRemovedOpacity,
    required this.pressDuration,
    required this.fadeDuration,
    required this.popDuration,
    required this.reelSpinDuration,
    required this.shimmerDuration,
    required this.standardCurve,
  });

  static const light = GameTokens(
    correct: RevealColors(
      top: ColorTokens.correctFillTop,
      bottom: ColorTokens.correctFill,
      edge: ColorTokens.correctEdge,
      glow: ColorTokens.correctGlow,
      heading: ColorTokens.correctText,
    ),
    wrong: RevealColors(
      top: ColorTokens.wrongFillTop,
      bottom: ColorTokens.wrongFill,
      edge: ColorTokens.wrongEdge,
      glow: ColorTokens.wrongGlow,
      heading: ColorTokens.wrongText,
    ),
    timerTrack: ColorTokens.timerTrack,
    timerFillStart: ColorTokens.timerFill,
    timerFillEnd: ColorTokens.timerFillEnd,
    timerPill: ColorTokens.timerPill,
    // Keyed by generation id, as in features/game/domain/eras.dart. 0 is "All eras".
    eraColors: {
      0: ColorTokens.eraAll,
      1: ColorTokens.eraGolden,
      2: ColorTokens.era80s,
      3: ColorTokens.era90s,
      4: ColorTokens.era2000s,
      5: ColorTokens.eraModern,
    },
    eraSelectedRing: ColorTokens.eraSelectedRing,
    answerDimOpacity: ColorTokens.answerDimOpacity,
    answerRemovedOpacity: ColorTokens.answerRemovedOpacity,
    pressDuration: MotionTokens.durationPress,
    fadeDuration: MotionTokens.durationFade,
    popDuration: MotionTokens.durationAnswerPop,
    reelSpinDuration: MotionTokens.durationReelSpin,
    shimmerDuration: MotionTokens.durationShimmer,
    standardCurve: MotionTokens.easingStandard,
  );

  final RevealColors correct;
  final RevealColors wrong;
  final Color timerTrack;
  final Color timerFillStart;
  final Color timerFillEnd;
  final Color timerPill;

  /// Era accent by generation id (0 = all eras, 1-5 as in the catalog).
  final Map<int, Color> eraColors;
  final Color eraSelectedRing;

  /// Opacity of the tiles that were not picked while the answer is shown.
  final double answerDimOpacity;

  /// Opacity of the tiles the hint took away.
  final double answerRemovedOpacity;

  final Duration pressDuration;
  final Duration fadeDuration;
  final Duration popDuration;
  final Duration reelSpinDuration;
  final Duration shimmerDuration;
  final Curve standardCurve;

  /// The accent for [generationId]. An unknown id gets the "all eras" color.
  Color eraColor(int generationId) => eraColors[generationId] ?? eraColors[0]!;

  @override
  GameTokens copyWith({RevealColors? correct, RevealColors? wrong}) =>
      GameTokens(
        correct: correct ?? this.correct,
        wrong: wrong ?? this.wrong,
        timerTrack: timerTrack,
        timerFillStart: timerFillStart,
        timerFillEnd: timerFillEnd,
        timerPill: timerPill,
        eraColors: eraColors,
        eraSelectedRing: eraSelectedRing,
        answerDimOpacity: answerDimOpacity,
        answerRemovedOpacity: answerRemovedOpacity,
        pressDuration: pressDuration,
        fadeDuration: fadeDuration,
        popDuration: popDuration,
        reelSpinDuration: reelSpinDuration,
        shimmerDuration: shimmerDuration,
        standardCurve: standardCurve,
      );

  /// There is one theme, so there is nothing to blend.
  @override
  GameTokens lerp(ThemeExtension<GameTokens>? other, double t) =>
      other is GameTokens && t >= 0.5 ? other : this;
}
