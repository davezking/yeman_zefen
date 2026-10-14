import 'session_config.dart';

/// How one round scored. See `docs/scoring.md`.
class RoundScore {
  const RoundScore({
    required this.points,
    required this.base,
    required this.bonus,
    required this.correct,
    required this.valid,
    required this.hintHalved,
  });

  /// What the round is worth, after the hint is applied. 0 when wrong or invalid.
  final int points;
  final int base;
  final int bonus;
  final bool correct;

  /// False when the response was faster than a person can react. Such a round
  /// scores 0 and flags the session.
  final bool valid;
  final bool hintHalved;
}

/// One answered round, as the scorer needs it.
class RoundAnswer {
  const RoundAnswer({
    required this.correct,
    required this.responseMs,
    this.hintUsed = false,
  });

  final bool correct;
  final int responseMs;
  final bool hintUsed;
}

class SessionScore {
  SessionScore(List<RoundScore> rounds) : rounds = List.unmodifiable(rounds);

  final List<RoundScore> rounds;

  int get total => rounds.fold(0, (sum, r) => sum + r.points);

  /// True when any round was invalid.
  bool get flagged => rounds.any((r) => !r.valid);
}

/// The scoring rules in `docs/scoring.md`. The server applies the same rules in
/// Phase 3 and decides the real score; this one is shown to the player
/// meanwhile.
///
/// All arithmetic is on integers, so the result is exact and cannot differ
/// between the app and the server because of floating point. "Round" means
/// round half up.
class Scorer {
  const Scorer();

  /// A response faster than this is not a human reaction (milliseconds).
  static const minResponseMs = 200;

  /// The answer window is the clip length plus this.
  static const windowExtraMs = 5000;

  /// Points for a correct answer in generation-guess mode.
  static const generationBase = 120;

  /// Generation-guess mode always uses a 10 s clip, with no difficulty tiers.
  static const generationClipMs = 10000;

  /// Base points before the speed bonus: 10 s = 100, 5 s = 150, 3 s = 200.
  /// Middle mode multiplies by 1.25, rounded half up (5 s gives 187.5, so 188).
  int basePoints(GameMode mode, Difficulty difficulty) {
    if (mode == GameMode.generation) return generationBase;
    final base = switch (difficulty) {
      Difficulty.easy => 100,
      Difficulty.medium => 150,
      Difficulty.hard => 200,
    };
    // round(base * 5 / 4) in integers.
    return mode == GameMode.middle ? (base * 5 + 2) ~/ 4 : base;
  }

  /// The time the player has to answer, in milliseconds: clip length plus 5 s.
  int windowMs(GameMode mode, Difficulty difficulty) {
    final clip = mode == GameMode.generation ? generationClipMs : difficulty.clipLengthMs;
    return clip + windowExtraMs;
  }

  /// The speed bonus: `round(0.5 * base * max(0, 1 - responseMs / windowMs))`.
  int speedBonus({required int base, required int responseMs, required int windowMs}) {
    if (responseMs >= windowMs) return 0;
    // round_half_up(base * (window - r) / (2 * window)) in integers.
    return (base * (windowMs - responseMs) + windowMs) ~/ (2 * windowMs);
  }

  RoundScore scoreRound({
    required GameMode mode,
    required Difficulty difficulty,
    required bool correct,
    required int responseMs,
    bool hintUsed = false,
  }) {
    final base = basePoints(mode, difficulty);
    if (responseMs < minResponseMs) {
      return RoundScore(
        points: 0,
        base: base,
        bonus: 0,
        correct: correct,
        valid: false,
        hintHalved: false,
      );
    }
    if (!correct) {
      return RoundScore(
        points: 0,
        base: base,
        bonus: 0,
        correct: false,
        valid: true,
        hintHalved: false,
      );
    }
    final bonus = speedBonus(
      base: base,
      responseMs: responseMs,
      windowMs: windowMs(mode, difficulty),
    );
    final full = base + bonus;
    // A hint halves the points: round(full / 2), half up.
    final points = hintUsed ? (full + 1) ~/ 2 : full;
    return RoundScore(
      points: points,
      base: base,
      bonus: bonus,
      correct: true,
      valid: true,
      hintHalved: hintUsed,
    );
  }

  SessionScore scoreSession({
    required GameMode mode,
    required Difficulty difficulty,
    required List<RoundAnswer> answers,
  }) {
    return SessionScore([
      for (final a in answers)
        scoreRound(
          mode: mode,
          difficulty: difficulty,
          correct: a.correct,
          responseMs: a.responseMs,
          hintUsed: a.hintUsed,
        ),
    ]);
  }
}
