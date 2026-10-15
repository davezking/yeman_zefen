import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/prototype/models.dart';
import 'package:yeman_zefen/prototype/round_simulation.dart';

/// The fake game follows `docs/scoring.md` and the timings in
/// `docs/design/screens.md`. Time here is the test's: each `pump` moves the
/// simulation's own 100 ms ticks.
void main() {
  const second = Duration(seconds: 1);

  void simTest(
    String name,
    Future<void> Function(WidgetTester tester, RoundSimulation sim) body, {
    PlaySettings settings = const PlaySettings(),
    int rounds = 10,
    int every = 3,
  }) {
    testWidgets(name, (tester) async {
      final sim = RoundSimulation(
        settings: settings,
        totalRounds: rounds,
        interstitialEvery: every,
        random: Random(7),
      );
      try {
        await body(tester, sim);
      } finally {
        sim.dispose();
      }
    });
  }

  int wrongIndex(RoundSimulation sim) =>
      [0, 1, 2, 3].firstWhere((i) => i != sim.view.correctIndex);

  group('a round', () {
    simTest('starts with the clip playing and a 15 s window on easy', (
      tester,
      sim,
    ) async {
      final v = sim.view;
      expect(v.phase, RoundPhase.answering);
      expect(v.clipPlaying, isTrue);
      expect(v.secondsLeft, 15);
      expect(v.timeFraction, 1);
      expect(v.roundNumber, 1);
      expect(v.hintAvailable, isTrue);
      expect(v.options.length, 4);
    });

    simTest('the window is the clip plus 5 s: 10 s on medium, 8 s on hard', (
      tester,
      sim,
    ) async {
      expect(sim.view.secondsLeft, 10);
    }, settings: const PlaySettings(difficulty: Difficulty.medium));

    simTest('hard has an 8 s window', (tester, sim) async {
      expect(sim.view.secondsLeft, 8);
    }, settings: const PlaySettings(difficulty: Difficulty.hard));

    simTest('the clip stops after its length while the timer runs on', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 9));
      expect(sim.view.clipPlaying, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(sim.view.clipPlaying, isFalse);
      expect(sim.view.phase, RoundPhase.answering);
      expect(sim.view.secondsLeft, 4);
    });

    simTest('a right answer scores by the rules and moves on after 1 s', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 2));
      sim.answer(sim.view.correctIndex);
      final v = sim.view;
      expect(v.phase, RoundPhase.correct);
      // docs/scoring.md E1: intro, easy, 2000 ms.
      expect(v.speedBonus, 43);
      expect(v.points, 143);
      expect(v.score, 143);
      expect(v.pickedIndex, v.correctIndex);

      await tester.pump(const Duration(milliseconds: 900));
      expect(sim.view.phase, RoundPhase.correct);
      await tester.pump(const Duration(milliseconds: 200));
      expect(sim.view.roundNumber, 2);
      expect(sim.view.phase, RoundPhase.answering);
    });

    simTest('a wrong answer shows the right one for 5 s, and a tap skips', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 3));
      sim.answer(wrongIndex(sim));
      expect(sim.view.phase, RoundPhase.wrong);
      expect(sim.view.points, 0);
      expect(sim.view.feedbackSecondsLeft, 5);

      await tester.pump(const Duration(seconds: 2));
      expect(sim.view.phase, RoundPhase.wrong);
      expect(sim.view.feedbackSecondsLeft, 3);
      sim.tapContinue();
      expect(sim.view.roundNumber, 2);
    });

    simTest('a wrong answer moves on by itself after 5 s', (tester, sim) async {
      sim.answer(wrongIndex(sim));
      await tester.pump(const Duration(milliseconds: 4900));
      expect(sim.view.roundNumber, 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(sim.view.roundNumber, 2);
    });

    simTest('a tap does not skip the 1 s of a right answer', (
      tester,
      sim,
    ) async {
      await tester.pump(second);
      sim.answer(sim.view.correctIndex);
      sim.tapContinue();
      expect(sim.view.roundNumber, 1);
    });

    simTest('running out of time is a time-out worth nothing', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 15));
      final v = sim.view;
      expect(v.phase, RoundPhase.timeout);
      expect(v.points, 0);
      expect(v.secondsLeft, 0);
      expect(sim.results.single.timedOut, isTrue);
      expect(sim.results.single.correct, isFalse);
      expect(v.feedbackSecondsLeft, 5);

      await tester.pump(const Duration(seconds: 5));
      expect(sim.view.roundNumber, 2);
    });

    simTest('an answer under 200 ms is invalid and scores nothing', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(milliseconds: 100));
      sim.answer(sim.view.correctIndex);
      expect(sim.view.points, 0);
    });

    simTest('answers are ignored once one is locked in', (tester, sim) async {
      await tester.pump(second);
      sim.answer(sim.view.correctIndex);
      final score = sim.score;
      sim.answer(wrongIndex(sim));
      expect(sim.score, score);
      expect(sim.results.length, 1);
    });
  });

  group('the hint', () {
    simTest('opens a sheet that stops the timer but not the clip', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 2));
      sim.requestHint();
      expect(sim.view.overlay, RoundOverlay.hintSheet);
      expect(sim.view.overlaySeconds, 8);
      expect(sim.view.timerPaused, isTrue);

      await tester.pump(const Duration(seconds: 3));
      expect(sim.view.secondsLeft, 13);
      expect(sim.view.overlaySeconds, 5);
      expect(sim.view.clipPlaying, isTrue);
    });

    simTest('closes itself after 8 s, and the timer picks up where it was', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 2));
      sim.requestHint();
      await tester.pump(const Duration(seconds: 8));
      expect(sim.view.overlay, RoundOverlay.none);
      expect(sim.view.hintUsed, isFalse);
      expect(sim.view.secondsLeft, 13);
      await tester.pump(second);
      expect(sim.view.secondsLeft, 12);
    });

    simTest('No thanks closes it at once', (tester, sim) async {
      sim.requestHint();
      sim.declineHint();
      expect(sim.view.overlay, RoundOverlay.none);
      expect(sim.view.hintAvailable, isTrue);
    });

    simTest('Watch ad removes two wrong answers and halves the points (E8)', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 2));
      sim.requestHint();
      sim.watchHintAd();
      expect(sim.view.overlay, RoundOverlay.rewardedAd);
      expect(sim.view.timerPaused, isTrue);
      await tester.pump(const Duration(seconds: 3));

      final v = sim.view;
      expect(v.overlay, RoundOverlay.none);
      expect(v.hintUsed, isTrue);
      expect(v.hintAvailable, isFalse);
      expect(v.removed.length, 2);
      expect(v.removed, isNot(contains(v.correctIndex)));
      // The ad did not cost any answering time.
      expect(v.secondsLeft, 13);

      // A removed answer cannot be picked.
      sim.answer(v.removed.first);
      expect(sim.view.phase, RoundPhase.answering);

      sim.answer(v.correctIndex);
      // docs/scoring.md E8: 143 halved, half up.
      expect(sim.view.points, 72);
    });

    simTest('one hint per round, and a new round has its hint back', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 2));
      sim.requestHint();
      sim.watchHintAd();
      await tester.pump(const Duration(seconds: 3));
      sim.requestHint();
      expect(sim.view.overlay, RoundOverlay.none);

      sim.answer(sim.view.correctIndex);
      await tester.pump(second);
      expect(sim.view.roundNumber, 2);
      expect(sim.view.hintAvailable, isTrue);
      expect(sim.view.removed, isEmpty);
    });
  });

  group('pausing', () {
    simTest('the background stops the clip and the timer, and back resumes', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 2));
      sim.setBackgrounded(true);
      expect(sim.view.timerPaused, isTrue);
      expect(sim.view.clipPlaying, isFalse);
      await tester.pump(const Duration(seconds: 6));
      expect(sim.view.secondsLeft, 13);

      sim.setBackgrounded(false);
      expect(sim.view.timerPaused, isFalse);
      expect(sim.view.clipPlaying, isTrue);
      await tester.pump(second);
      expect(sim.view.secondsLeft, 12);
    });

    simTest('the background also holds a reveal on screen', (
      tester,
      sim,
    ) async {
      sim.answer(wrongIndex(sim));
      sim.setBackgrounded(true);
      await tester.pump(const Duration(seconds: 10));
      expect(sim.view.phase, RoundPhase.wrong);
      expect(sim.view.roundNumber, 1);
    });

    simTest('Leave asks first and stops the timer; Keep playing resumes', (
      tester,
      sim,
    ) async {
      await tester.pump(const Duration(seconds: 2));
      sim.requestLeave();
      expect(sim.view.overlay, RoundOverlay.leaveDialog);
      expect(sim.view.timerPaused, isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(sim.view.secondsLeft, 13);

      sim.cancelLeave();
      expect(sim.view.overlay, RoundOverlay.none);
      await tester.pump(second);
      expect(sim.view.secondsLeft, 12);
      expect(sim.left, isFalse);
    });

    simTest('Leave from the hint sheet goes back to the sheet when cancelled', (
      tester,
      sim,
    ) async {
      sim.requestHint();
      await tester.pump(const Duration(seconds: 2));
      sim.requestLeave();
      sim.cancelLeave();
      expect(sim.view.overlay, RoundOverlay.hintSheet);
      expect(sim.view.overlaySeconds, 6);
    });

    simTest('confirming Leave ends the game with no score', (
      tester,
      sim,
    ) async {
      sim.requestLeave();
      sim.confirmLeave();
      expect(sim.left, isTrue);
      expect(sim.finished, isFalse);
    });
  });

  group('a game', () {
    simTest('an ad follows every 3rd round, then the next round starts', (
      tester,
      sim,
    ) async {
      for (var r = 1; r <= 3; r++) {
        await tester.pump(const Duration(seconds: 2));
        sim.answer(sim.view.correctIndex);
        await tester.pump(second);
        if (r < 3) expect(sim.view.roundNumber, r + 1);
      }
      expect(sim.view.overlay, RoundOverlay.interstitial);
      expect(sim.view.roundNumber, 3);
      expect(sim.view.overlaySeconds, 3);

      await tester.pump(const Duration(seconds: 2));
      expect(sim.view.overlay, RoundOverlay.interstitial);
      await tester.pump(const Duration(milliseconds: 600));
      expect(sim.view.overlay, RoundOverlay.none);
      expect(sim.view.roundNumber, 4);
      expect(sim.view.secondsLeft, 15);
    });

    simTest('ten rounds end the game with every round recorded', (
      tester,
      sim,
    ) async {
      for (var r = 1; r <= 10; r++) {
        await tester.pump(const Duration(seconds: 2));
        sim.answer(sim.view.correctIndex);
        await tester.pump(second);
      }
      expect(sim.finished, isTrue);
      expect(sim.results.length, 10);
      expect(sim.results.every((r) => r.correct), isTrue);
      expect(sim.score, 1430);
      expect(sim.newBest, isTrue);
    }, every: 0);

    testWidgets('a game beats the best only with a higher score', (
      tester,
    ) async {
      Future<bool> play(int? best) async {
        final sim = RoundSimulation(
          settings: const PlaySettings(),
          totalRounds: 1,
          interstitialEvery: 0,
          bestScore: best,
          random: Random(7),
        );
        await tester.pump(const Duration(seconds: 2));
        sim.answer(sim.view.correctIndex);
        await tester.pump(const Duration(seconds: 1));
        final beat = sim.newBest;
        sim.dispose();
        return beat;
      }

      expect(await play(null), isTrue);
      expect(await play(100), isTrue);
      expect(await play(143), isFalse);
      expect(await play(5000), isFalse);
    });

    simTest(
      'three rounds are three rounds',
      (tester, sim) async {
        for (var r = 1; r <= 3; r++) {
          sim.answer(wrongIndex(sim));
          sim.tapContinue();
        }
        expect(sim.finished, isTrue);
        expect(sim.results.length, 3);
        expect(sim.score, 0);
      },
      rounds: 3,
      every: 0,
    );
  });

  group('the questions', () {
    simTest(
      'asking for the artist gives four different singers',
      (tester, sim) async {
        for (var r = 0; r < 5; r++) {
          final v = sim.view;
          expect(v.kind, QuestionKind.artist);
          final names = [for (final o in v.options) o.track!.artistLatin];
          expect(names.toSet().length, 4);
          expect(
            v.options[v.correctIndex].track!.artistLatin,
            v.track.artistLatin,
          );
          sim.answer(v.correctIndex);
          await tester.pump(second);
        }
      },
      settings: const PlaySettings(guess: GuessTarget.artist),
      every: 0,
    );

    simTest('asking for the song gives four different titles', (
      tester,
      sim,
    ) async {
      final v = sim.view;
      expect(v.kind, QuestionKind.song);
      expect({for (final o in v.options) o.track!.titleLatin}.length, 4);
      expect(v.options[v.correctIndex].track!.titleLatin, v.track.titleLatin);
    });

    simTest(
      'Which Era? offers four eras, one of them right, in a 15 s window',
      (tester, sim) async {
        final v = sim.view;
        expect(v.kind, QuestionKind.era);
        final ids = [for (final o in v.options) o.generationId!];
        expect(ids.toSet().length, 4);
        expect(ids, isNot(contains(EraId.all)));
        expect(ids[v.correctIndex], v.track.generationId);
        expect(v.secondsLeft, 15);
      },
      settings: const PlaySettings(
        mode: GameMode.era,
        difficulty: Difficulty.hard,
      ),
    );

    simTest(
      'an era filter only asks about that era',
      (tester, sim) async {
        for (var r = 0; r < 4; r++) {
          expect(sim.view.track.generationId, EraId.eighties);
          sim.answer(sim.view.correctIndex);
          await tester.pump(second);
        }
      },
      settings: const PlaySettings(generationId: EraId.eighties),
      every: 0,
    );

    simTest('Middle mode pays a quarter more (E5)', (tester, sim) async {
      await tester.pump(const Duration(seconds: 2));
      sim.answer(sim.view.correctIndex);
      expect(sim.view.points, 179);
    }, settings: const PlaySettings(mode: GameMode.middle));
  });
}
