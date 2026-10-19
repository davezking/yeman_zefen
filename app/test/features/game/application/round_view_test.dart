import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'session_kit.dart';

const _song = SessionConfig(mode: GameMode.intro, difficulty: Difficulty.medium, questions: QuestionMix.song, rounds: 3);

/// What the round screen is given while a round runs: the running score, the names for the reveal,
/// the clock to count down from, and how long a result stays up.
void main() {
  late SessionKit kit;

  setUp(() async {
    kit = await SessionKit.create(wrongFeedback: const Duration(seconds: 5));
  });

  tearDown(() => kit.dispose());

  group('score', () {
    test('runs from round to round, and includes a round once it is answered', () async {
      kit.start(_song);
      var round = await kit.untilRound(1, RoundPhase.answering);
      expect((round.score, round.number), (0, 1));

      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.score, 206);
      expect(round.points, 206);
      expect(round.speedBonus, 56, reason: 'medium: 150 base, 56 for answering in 2.5 s');
      kit.endFeedback();

      round = await kit.untilRound(2, RoundPhase.answering);
      expect(round.score, 206, reason: 'what the first round earned');

      kit.clockMs += 2500;
      kit.controller.answer(kit.wrongOption());
      round = await kit.untilRound(2, RoundPhase.feedback);
      expect((round.score, round.points, round.speedBonus), (206, 0, 0));
    });
  });

  group('the reveal', () {
    test('carries the song and its singer once the round is up, in both scripts', () async {
      kit.start(_song);
      final round = await kit.untilRound(1, RoundPhase.answering);
      final id = kit.playingTrackId();
      expect(round.trackName.latin, 'Song $id');
      expect(round.trackName.am, 'ዘፈን $id');
      expect(round.artistName.isEmpty, isFalse);
    });
  });

  group('the clock', () {
    test('answering carries the time the answer clock started, which a pause moves back', () async {
      kit.start(_song);
      var round = await kit.untilRound(1, RoundPhase.answering);
      expect(round.answerClockStartMs, kit.clockMs, reason: 'it starts when the audio plays');

      kit.clockMs += 4000;
      kit.controller.pauseForBackground();
      await kit.untilRound(1, RoundPhase.interrupted);
      kit.clockMs += 30000; // away for a long time
      kit.controller.resume();
      round = await kit.untilRound(1, RoundPhase.answering, attempt: 2);
      expect(round.answerClockStartMs, kit.clockMs - 4000, reason: 'the 4 s already used still count');
      expect(round.remainingMs, 6000);
    });

    test('the answered round keeps what was left when the answer stopped the clock', () async {
      kit.start(_song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 3000;
      kit.controller.answer(kit.correctOption());
      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.remainingMs, 7000);
      expect(round.answerClockStartMs, isNull);
    });
  });

  group('the clip', () {
    test('plays from the start of the answer window until it ends, which can be before the window does', () async {
      kit.start(_song);
      var round = await kit.untilRound(1, RoundPhase.answering);
      expect(round.clipPlaying, isTrue);

      kit.voices.firstWhere((v) => v.playing).finish();
      await kit.until(() => kit.state.round!.clipPlaying == false, what: 'the reels to stop');
      round = kit.state.round!;
      expect(round.phase, RoundPhase.answering, reason: 'the player can still answer');
    });

    test('is not playing in feedback', () async {
      kit.start(_song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.clipPlaying, isFalse);
    });
  });

  group('feedback pacing', () {
    test('a right answer moves on after 1 s and a tap cannot hurry it', () async {
      kit.start(_song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.feedbackMs, 1000);
      expect(round.feedbackStartedAtMs, kit.clockMs);

      kit.controller.skipFeedback();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(kit.state.round!.number, 1, reason: 'a right answer is not skippable');
      kit.endFeedback();
      await kit.untilRound(2, RoundPhase.answering);
    });

    test('a wrong answer stays for 5 s, and a tap moves on at once', () async {
      kit.start(_song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.wrongOption());
      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.feedbackMs, 5000);

      kit.controller.skipFeedback();
      await kit.untilRound(2, RoundPhase.answering);
    });

    test('a time-out stays for 5 s too, and a tap moves on', () async {
      kit.start(_song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.endWindow(10000);
      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect((round.timedOut, round.feedbackMs, round.points), (true, 5000, 0));

      kit.controller.skipFeedback();
      await kit.untilRound(2, RoundPhase.answering);
    });

    test('skipping while a round is being answered does nothing', () async {
      kit.start(_song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.controller.skipFeedback();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(kit.state.round!.phase, RoundPhase.answering);
    });
  });

  group('pausing between rounds', () {
    test('Resume clears a pause that had nothing to resume, so the next clip plays by itself', () async {
      kit.start(_song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);

      // The "Leave this game?" question was open over the feedback, then dismissed.
      kit.controller.pauseForBackground();
      kit.controller.resume();
      kit.endFeedback();

      final round = await kit.untilRound(2, RoundPhase.answering);
      expect(round.attempt, 1, reason: 'no paused notice appeared');
    });
  });
}
