import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/domain/scorer.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'doc_files.dart';

/// One row of the worked-examples table in docs/scoring.md.
class _Example {
  _Example(List<String> c)
      : id = c[0],
        mode = GameMode.values.byName(c[1]),
        difficulty = c[2] == '-' ? Difficulty.easy : Difficulty.values.byName(c[2]),
        correct = c[3] == 'yes',
        responseMs = int.parse(c[4]),
        hint = c[5] == 'yes',
        base = int.parse(c[6]),
        window = int.parse(c[7]),
        bonus = int.parse(c[8]),
        points = int.parse(c[9]),
        valid = c[10] == 'yes';

  final String id;
  final GameMode mode;
  final Difficulty difficulty;
  final bool correct;
  final int responseMs;
  final bool hint;
  final int base;
  final int window;
  final int bonus;
  final int points;
  final bool valid;
}

List<_Example> _examplesFromDoc() {
  final rows = <_Example>[];
  final exampleRow = RegExp(r'^\| E\d+ \|');
  for (final line in readDoc('scoring.md').split('\n')) {
    if (!exampleRow.hasMatch(line)) continue;
    final cells = line.split('|').map((c) => c.trim()).toList();
    // A row starts and ends with '|', so the first and last cells are empty.
    rows.add(_Example(cells.sublist(1, cells.length - 1)));
  }
  return rows;
}

void main() {
  const scorer = Scorer();

  group('worked examples in docs/scoring.md', () {
    final examples = _examplesFromDoc();

    test('the table was read, with every example', () {
      expect(examples.map((e) => e.id), [for (var i = 1; i <= 17; i++) 'E$i']);
    });

    for (final e in examples) {
      test('${e.id}: ${e.mode.name} ${e.difficulty.name} '
          '${e.correct ? 'correct' : 'wrong'} at ${e.responseMs} ms${e.hint ? ' with hint' : ''}', () {
        final score = scorer.scoreRound(
          mode: e.mode,
          difficulty: e.difficulty,
          correct: e.correct,
          responseMs: e.responseMs,
          hintUsed: e.hint,
        );
        expect(score.points, e.points, reason: 'points');
        expect(score.valid, e.valid, reason: 'valid');
        expect(scorer.basePoints(e.mode, e.difficulty), e.base, reason: 'base');
        expect(scorer.windowMs(e.mode, e.difficulty), e.window, reason: 'window');
        if (e.valid && e.correct) {
          expect(score.bonus, e.bonus, reason: 'bonus');
        }
      });
    }

    test('the session example adds up', () {
      final session = scorer.scoreSession(
        mode: GameMode.intro,
        difficulty: Difficulty.easy,
        answers: const [
          RoundAnswer(correct: true, responseMs: 2000), // E1
          RoundAnswer(correct: false, responseMs: 2000), // E4
          RoundAnswer(correct: true, responseMs: 2000, hintUsed: true), // E8
        ],
      );
      expect(session.rounds.map((r) => r.points), [143, 0, 72]);
      expect(session.total, 215);
      expect(session.flagged, isFalse);

      final withInvalid = scorer.scoreSession(
        mode: GameMode.intro,
        difficulty: Difficulty.easy,
        answers: const [
          RoundAnswer(correct: true, responseMs: 2000),
          RoundAnswer(correct: false, responseMs: 2000),
          RoundAnswer(correct: true, responseMs: 2000, hintUsed: true),
          RoundAnswer(correct: true, responseMs: 199), // E12
        ],
      );
      expect(withInvalid.total, 215);
      expect(withInvalid.flagged, isTrue);
    });
  });

  group('base points and window', () {
    test('base by difficulty in intro mode', () {
      expect(scorer.basePoints(GameMode.intro, Difficulty.easy), 100);
      expect(scorer.basePoints(GameMode.intro, Difficulty.medium), 150);
      expect(scorer.basePoints(GameMode.intro, Difficulty.hard), 200);
    });

    test('middle mode multiplies by 1.25 and rounds half up', () {
      expect(scorer.basePoints(GameMode.middle, Difficulty.easy), 125);
      expect(scorer.basePoints(GameMode.middle, Difficulty.medium), 188); // 187.5
      expect(scorer.basePoints(GameMode.middle, Difficulty.hard), 250);
    });

    test('generation mode is 120 on a 10 s clip whatever the difficulty', () {
      for (final d in Difficulty.values) {
        expect(scorer.basePoints(GameMode.generation, d), 120);
        expect(scorer.windowMs(GameMode.generation, d), 15000);
      }
    });

    test('the window is the clip length plus 5 s', () {
      expect(scorer.windowMs(GameMode.intro, Difficulty.easy), 15000);
      expect(scorer.windowMs(GameMode.intro, Difficulty.medium), 10000);
      expect(scorer.windowMs(GameMode.intro, Difficulty.hard), 8000);
      expect(scorer.windowMs(GameMode.middle, Difficulty.hard), 8000);
    });
  });

  group('speed bonus', () {
    test('is half the base at the moment audio starts, rounded half up', () {
      expect(scorer.speedBonus(base: 100, responseMs: 0, windowMs: 15000), 50);
      expect(scorer.speedBonus(base: 125, responseMs: 0, windowMs: 15000), 63); // 62.5
    });

    test('is 0 at the window and after it', () {
      expect(scorer.speedBonus(base: 100, responseMs: 15000, windowMs: 15000), 0);
      expect(scorer.speedBonus(base: 100, responseMs: 99999, windowMs: 15000), 0);
    });

    test('never rises as the response gets slower', () {
      for (final base in [100, 120, 125, 150, 188, 200, 250]) {
        for (final window in [8000, 10000, 15000]) {
          var previous = scorer.speedBonus(base: base, responseMs: 0, windowMs: window);
          for (var r = 1; r <= window + 500; r += 13) {
            final bonus = scorer.speedBonus(base: base, responseMs: r, windowMs: window);
            expect(bonus, lessThanOrEqualTo(previous), reason: 'base $base window $window at $r ms');
            expect(bonus, greaterThanOrEqualTo(0));
            previous = bonus;
          }
        }
      }
    });

    test('matches the formula round(0.5 * base * (1 - r / window)) away from exact ties', () {
      for (final base in [100, 125, 150, 188, 200, 250]) {
        for (final window in [8000, 10000, 15000]) {
          for (var r = 200; r < window; r += 37) {
            final exact = 0.5 * base * (1 - r / window);
            if ((exact * 2 - (exact * 2).round()).abs() < 1e-6) continue; // an exact .5 tie
            expect(
              scorer.speedBonus(base: base, responseMs: r, windowMs: window),
              exact.round(),
              reason: 'base $base window $window at $r ms',
            );
          }
        }
      }
    });
  });

  group('rounds', () {
    int points({
      GameMode mode = GameMode.intro,
      Difficulty difficulty = Difficulty.easy,
      bool correct = true,
      int ms = 2000,
      bool hint = false,
    }) =>
        scorer
            .scoreRound(
              mode: mode,
              difficulty: difficulty,
              correct: correct,
              responseMs: ms,
              hintUsed: hint,
            )
            .points;

    test('a hint halves the points, rounding half up', () {
      expect(points(hint: false), 143);
      expect(points(hint: true), 72); // 71.5
      expect(points(difficulty: Difficulty.medium, ms: 1500, hint: true), 107); // 214 / 2
    });

    test('a hint on a wrong answer is still 0', () {
      expect(points(correct: false, hint: true), 0);
    });

    test('under 200 ms is invalid, scores 0 and keeps the answer as given', () {
      final right = scorer.scoreRound(
        mode: GameMode.intro,
        difficulty: Difficulty.easy,
        correct: true,
        responseMs: 199,
      );
      expect(right.valid, isFalse);
      expect(right.points, 0);
      expect(right.correct, isTrue);
      expect(right.hintHalved, isFalse);

      final wrong = scorer.scoreRound(
        mode: GameMode.intro,
        difficulty: Difficulty.easy,
        correct: false,
        responseMs: 0,
      );
      expect(wrong.valid, isFalse);
    });

    test('exactly 200 ms is valid', () {
      final score = scorer.scoreRound(
        mode: GameMode.intro,
        difficulty: Difficulty.easy,
        correct: true,
        responseMs: 200,
      );
      expect(score.valid, isTrue);
      expect(score.points, 149);
    });

    test('a correct answer after the window earns the base and no bonus', () {
      final score = scorer.scoreRound(
        mode: GameMode.intro,
        difficulty: Difficulty.hard,
        correct: true,
        responseMs: 8001,
      );
      expect(score.bonus, 0);
      expect(score.points, 200);
    });

    test('reports base, bonus and whether the hint applied', () {
      final score = scorer.scoreRound(
        mode: GameMode.middle,
        difficulty: Difficulty.medium,
        correct: true,
        responseMs: 1500,
        hintUsed: true,
      );
      expect(score.base, 188);
      expect(score.bonus, 80);
      expect(score.hintHalved, isTrue);
      expect(score.points, 134); // (188 + 80) / 2
    });
  });

  test('an empty session scores 0 and is not flagged', () {
    final session = scorer.scoreSession(
      mode: GameMode.intro,
      difficulty: Difficulty.easy,
      answers: const [],
    );
    expect(session.total, 0);
    expect(session.flagged, isFalse);
  });
}
