import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/audio/clip_voice.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/data/session_store.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'session_kit.dart';

const song = SessionConfig(mode: GameMode.intro, difficulty: Difficulty.medium, questions: QuestionMix.song);
const short = SessionConfig(mode: GameMode.intro, difficulty: Difficulty.medium, questions: QuestionMix.song, rounds: 2);

void main() {
  late SessionKit kit;

  setUp(() async {
    kit = await SessionKit.create();
  });

  tearDown(() => kit.dispose());

  Future<List<Map<String, dynamic>>> savedRounds(String sessionId) async {
    final row = await (kit.db.select(kit.db.pendingSessions)..where((t) => t.id.equals(sessionId))).getSingle();
    return ((jsonDecode(row.payloadJson) as Map<String, dynamic>)['rounds'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  group('a full session', () {
    test('plays 10 rounds, scores them and saves the session', () async {
      kit.start(song);
      await kit.playAll(pick: kit.correctOption);

      final summary = kit.state.summary!;
      expect(kit.state.phase, SessionPhase.finished);
      expect(summary.rounds, hasLength(10));
      // Medium: base 150, window 10 s. At 2500 ms the bonus is 56, so 206 a round.
      expect(summary.rounds.every((r) => r.points == 206 && r.correct && r.valid), isTrue);
      expect(summary.totalScore, 2060);
      expect(summary.skipped, 0);
      expect(summary.flagged, isFalse);
      expect(summary.isNewBest, isTrue);
      expect(summary.bestBefore, isNull);
      expect(summary.saveError, isNull);
    });

    test('stores a payload in pending_sessions that matches the documented shape', () async {
      kit.start(song);
      await kit.playAll(pick: kit.correctOption);

      final row = await kit.db.select(kit.db.pendingSessions).getSingle();
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;

      expect(payload.keys.toList(), [
        'id', 'mode', 'generationId', 'difficulty', 'clientStartedAt', 'clientEndedAt', 'offline', 'rounds', 'ads',
      ]);
      expect(payload['id'], 'session-1');
      expect(row.id, 'session-1');
      expect(payload['mode'], 'intro');
      expect(payload['generationId'], 0);
      expect(payload['difficulty'], 'medium');
      expect(payload['offline'], isTrue);
      expect(payload['clientStartedAt'], lessThan(payload['clientEndedAt'] as int));
      expect(payload['ads'], {'interstitialShown': 0, 'rewardedCompleted': 0});

      final rounds = (payload['rounds'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(rounds, hasLength(10));
      for (final r in rounds) {
        expect(r.keys.toList(), ['trackId', 'question', 'optionIds', 'chosenId', 'responseMs', 'hintUsed']);
        expect(r['question'], 'song');
        expect((r['optionIds'] as List).toSet(), hasLength(4));
        expect(r['chosenId'], r['trackId']);
        expect(r['responseMs'], 2500);
        expect(r['hintUsed'], isFalse);
      }
      expect(rounds.map((r) => r['trackId']).toSet(), hasLength(10));
    });

    test('times the answer from when audio started, not from when the round began', () async {
      // Loading the clip takes 900 ms on the clock. That must not count.
      for (final v in kit.voices) {
        v.onStart = () => kit.clockMs += 900;
      }
      kit.start(short);
      await kit.playAll(pick: kit.correctOption, responseMs: 1234);

      final rounds = await savedRounds('session-1');
      expect(rounds.map((r) => r['responseMs']), [1234, 1234]);
    });

    test('shows the answer, the right option and the points for a correct answer', () async {
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      expect(kit.state.round!.correctId, isNull, reason: 'the answer is not shown before it is given');
      final correct = kit.correctOption();
      kit.clockMs += 2500;
      kit.controller.answer(correct);

      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.chosenId, correct);
      expect(round.correctId, correct);
      expect(round.isCorrect, isTrue);
      expect(round.points, 206);
      expect(round.timedOut, isFalse);
    });

    test('scores a wrong answer 0 and shows the right one', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      final correct = kit.correctOption();
      final wrong = kit.wrongOption();
      kit.clockMs += 2500;
      kit.controller.answer(wrong);

      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.chosenId, wrong);
      expect(round.correctId, correct);
      expect(round.isCorrect, isFalse);
      expect(round.points, 0);

      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);
      final summary = kit.state.summary!;
      expect(summary.rounds.first.correct, isFalse);
      expect(summary.rounds.first.points, 0);
      expect(summary.rounds.first.correctName.am, startsWith('ዘፈን'));
      expect(summary.rounds.first.chosenName, isNot(summary.rounds.first.correctName));
      expect(summary.totalScore, 206);
    });

    test('scores an answer under 200 ms as 0 and flags the session', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 150;
      kit.controller.answer(kit.correctOption());

      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.points, 0);
      expect(round.valid, isFalse);

      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);
      expect(kit.state.summary!.flagged, isTrue);
      expect(kit.state.summary!.rounds.first.valid, isFalse);
      final rounds = await savedRounds('session-1');
      expect(rounds.first['responseMs'], 150, reason: 'the time is recorded as it was, for the server to judge');
    });

    test('the answer window is the clip length plus 5 s', () async {
      kit.start(song);
      expect((await kit.untilRound(1, RoundPhase.answering)).windowMs, 10000);
      expect(kit.timers.any((t) => t.isActive && t.duration == const Duration(milliseconds: 10000)), isTrue);

      kit.controller.leave();
      kit.start(const SessionConfig(mode: GameMode.intro, difficulty: Difficulty.hard, questions: QuestionMix.song));
      expect((await kit.untilRound(1, RoundPhase.answering)).windowMs, 8000);
    });

    test('artist questions offer artists', () async {
      kit.start(const SessionConfig(mode: GameMode.intro, difficulty: Difficulty.easy, questions: QuestionMix.artist));
      final round = await kit.untilRound(1, RoundPhase.answering);

      expect(round.kind, QuestionKind.artist);
      expect(round.options.every((o) => o.name.latin!.contains('Artist')), isTrue);
      expect(round.options.map((o) => o.id).toSet(), hasLength(4));
      expect(round.options.map((o) => o.id), contains(kit.correctOption()));
    });

    test('the middle clip plays in middle mode', () async {
      kit.start(const SessionConfig(mode: GameMode.middle, difficulty: Difficulty.medium, questions: QuestionMix.song));
      await kit.untilRound(1, RoundPhase.answering);
      expect(kit.voices.firstWhere((v) => v.playing).loads.last.$1, endsWith('-middle.mp3'));
    });

    test('plays the clip only up to the difficulty limit', () async {
      kit.start(const SessionConfig(mode: GameMode.intro, difficulty: Difficulty.hard, questions: QuestionMix.song));
      await kit.untilRound(1, RoundPhase.answering);
      expect(kit.voices.firstWhere((v) => v.playing).loads.last.$2, const Duration(seconds: 3));
    });
  });

  group('answers', () {
    test('an option that is not on screen is ignored', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.controller.answer(-5);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(kit.state.round!.phase, RoundPhase.answering);
    });

    test('a second tap in the same round is ignored', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      final first = kit.correctOption();
      final other = kit.wrongOption();
      kit.clockMs += 2500;
      kit.controller.answer(first);
      kit.clockMs += 500;
      kit.controller.answer(other);
      await kit.untilRound(1, RoundPhase.feedback);

      expect(kit.state.round!.chosenId, first);
      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);
      expect((await savedRounds('session-1')).first['responseMs'], 2500);
    });

    test('a tap during the feedback pause is ignored', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);

      kit.controller.answer(kit.state.round!.options.last.id);
      expect(kit.state.round!.chosenId, isNotNull);
      expect(kit.state.round!.phase, RoundPhase.feedback);
    });

    test('the audio stops as soon as an option is tapped', () async {
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      final playing = kit.voices.firstWhere((v) => v.playing);

      kit.controller.answer(kit.correctOption());

      expect(playing.playing, isFalse, reason: 'stopped in the same turn as the tap');
    });

    test('running out of time records no answer and 0 points', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);

      kit.endWindow(10000);
      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.timedOut, isTrue);
      expect(round.points, 0);
      expect(round.chosenId, isNull);
      expect(round.correctId, isNotNull);

      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);
      final rounds = await savedRounds('session-1');
      expect(rounds.first['chosenId'], isNull);
      expect(rounds.first['responseMs'], 10000);
      expect(kit.state.summary!.rounds.first.chosenName, isNull);
    });
  });

  group('best score and history', () {
    test('a later session is a new best only when it scores more', () async {
      kit.start(short);
      await kit.playAll(pick: kit.correctOption); // 2 x 206 = 412
      expect(kit.state.summary!.isNewBest, isTrue);

      kit.start(short);
      await kit.playAll(pick: kit.wrongOption); // 0
      final worse = kit.state.summary!;
      expect(worse.totalScore, 0);
      expect(worse.isNewBest, isFalse);
      expect(worse.bestBefore, 412);

      kit.start(short);
      await kit.playAll(pick: kit.correctOption, responseMs: 500); // 2 x 221
      final better = kit.state.summary!;
      expect(better.totalScore, 442);
      expect(better.isNewBest, isTrue);
      expect(better.bestBefore, 412);
      expect(await SessionStore(kit.db).bestScore(GameMode.intro, 0), 442);
    });

    test('the next session avoids the tracks of the one before', () async {
      kit.start(song);
      await kit.playAll(pick: kit.correctOption);
      final first = (await savedRounds('session-1')).map((r) => r['trackId']).toSet();

      kit.start(song);
      await kit.playAll(pick: kit.correctOption);
      final second = (await savedRounds('session-2')).map((r) => r['trackId']).toSet();

      expect(first, hasLength(10));
      expect(second, hasLength(10));
      expect(first.intersection(second), isEmpty);
    });

    test('a session is online only if the device was online at the start and the end', () async {
      kit.offline = false;
      kit.start(short);
      await kit.playAll(pick: kit.correctOption);
      expect((jsonDecode((await kit.db.select(kit.db.pendingSessions).getSingle()).payloadJson) as Map)['offline'], isFalse);

      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.offline = true; // the connection drops during the session
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);
      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);
      final second = await (kit.db.select(kit.db.pendingSessions)..where((t) => t.id.equals('session-2'))).getSingle();
      expect((jsonDecode(second.payloadJson) as Map)['offline'], isTrue);
    });
  });

  group('clips that cannot be played', () {
    test('a missing clip file skips that round and is counted', () async {
      // Era 1 is the even tracks: 15 tracks. All 15 are played, and one clip is missing.
      kit.existing.remove(kit.clipPath(8));
      kit.start(const SessionConfig(
        mode: GameMode.intro,
        difficulty: Difficulty.medium,
        generationId: 1,
        questions: QuestionMix.song,
        rounds: 15,
      ));
      await kit.playAll(pick: kit.correctOption);

      final summary = kit.state.summary!;
      expect(summary.rounds, hasLength(14));
      expect(summary.skipped, 1);
      expect(await SessionStore(kit.db).clipErrorCount(), 1);
      expect(summary.totalScore, 14 * 206);
      expect(await savedRounds('session-1'), hasLength(14));
      expect((await savedRounds('session-1')).map((r) => r['trackId']), isNot(contains(8)));
      // The skipped round used up its number, so the numbers are 1-15 with one gap.
      final numbers = summary.rounds.map((r) => r.number).toList();
      expect(numbers.toSet(), hasLength(14));
      expect(numbers.every((n) => n >= 1 && n <= 15), isTrue);
    });

    test('when no clip can be played the session fails and nothing is saved', () async {
      kit.existing.clear();
      kit.start(song);
      await kit.untilPhase(SessionPhase.failed);

      expect(kit.state.error?.problem, SessionProblem.clipsFailed);
      expect(kit.state.error?.count, 10);
      expect(await kit.db.select(kit.db.pendingSessions).get(), isEmpty);
      expect(await kit.db.select(kit.db.localBests).get(), isEmpty);
      expect(await SessionStore(kit.db).clipErrorCount(), 10);
    });

    test('when the audio engine fails for every clip the session fails the same way', () async {
      for (final v in kit.voices) {
        v.startError = const ClipPlaybackException('decoder error');
      }
      kit.start(short);
      await kit.untilPhase(SessionPhase.failed);

      expect(kit.state.error?.problem, SessionProblem.clipsFailed);
      expect(kit.state.error?.count, 2);
      expect(await kit.db.select(kit.db.pendingSessions).get(), isEmpty);
      expect(await SessionStore(kit.db).clipErrorCount(), 2);
    });
  });

  group('when a session cannot start', () {
    test('nothing is installed', () async {
      final empty = await SessionKit.create(tracks: 0);
      addTearDown(empty.dispose);
      empty.start(song);
      await empty.untilPhase(SessionPhase.failed);
      expect(empty.state.error?.problem, SessionProblem.noSongs);
    });

    test('too few songs for 4 options', () async {
      final few = await SessionKit.create(tracks: 3);
      addTearDown(few.dispose);
      few.start(song);
      await few.untilPhase(SessionPhase.failed);
      expect(few.state.error?.problem, SessionProblem.tooFewSongs);
    });

    test('the era has no songs', () async {
      kit.start(const SessionConfig(mode: GameMode.intro, difficulty: Difficulty.easy, generationId: 5));
      await kit.untilPhase(SessionPhase.failed);
      expect(kit.state.error?.problem, SessionProblem.noSongsInEra);
      expect(kit.state.error?.generationId, 5);
    });
  });

  group('interruptions', () {
    test('a call pauses the round and stops its timer', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);

      kit.interruptions.add(null);
      await kit.untilRound(1, RoundPhase.interrupted);

      expect(kit.timers.where((t) => t.duration == const Duration(milliseconds: 10000)).every((t) => !t.isActive), isTrue);
      expect(kit.voices.any((v) => v.playing), isFalse);
    });

    test('resuming plays the clip again but keeps the time already used', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 4000; // time before the call, which still counts
      kit.interruptions.add(null);
      await kit.untilRound(1, RoundPhase.interrupted);
      kit.clockMs += 60000; // the call, which does not

      kit.controller.resume();
      final resumed = await kit.untilRound(1, RoundPhase.answering, attempt: 2);
      expect(resumed.remainingMs, 6000);
      expect(kit.voices.any((v) => v.playing), isTrue, reason: 'the clip plays again');
      expect(kit.timers.where((t) => t.isActive && t.duration == const Duration(milliseconds: 6000)), hasLength(1),
          reason: 'the window only has what was left');
      kit.clockMs += 1000;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);
      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);

      final rounds = await savedRounds('session-1');
      expect(rounds, hasLength(2), reason: 'the interrupted round is recorded once');
      expect(rounds.first['responseMs'], 5000, reason: '4 s before the call and 1 s after it');
    });

    test('pausing twice adds up the time from both attempts', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 3000;
      kit.controller.pauseForBackground();
      await kit.untilRound(1, RoundPhase.interrupted);
      kit.controller.resume();
      await kit.untilRound(1, RoundPhase.answering, attempt: 2);
      kit.clockMs += 2000;
      kit.interruptions.add(null);
      await kit.untilRound(1, RoundPhase.interrupted, attempt: 2);
      kit.controller.resume();

      expect((await kit.untilRound(1, RoundPhase.answering, attempt: 3)).remainingMs, 5000);
      kit.clockMs += 500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);
      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);

      expect((await savedRounds('session-1')).first['responseMs'], 5500);
    });

    test('a pause after the window has run out times the round out', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 10000; // the window is over, but its timer has not fired yet
      kit.interruptions.add(null);

      final round = await kit.untilRound(1, RoundPhase.feedback);
      expect(round.timedOut, isTrue);
      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);

      final rounds = await savedRounds('session-1');
      expect(rounds.first['chosenId'], isNull);
      expect(rounds.first['responseMs'], 10000);
    });

    test('a call before the audio started pauses the round too', () async {
      for (final v in kit.voices) {
        v.startDelay = const Duration(milliseconds: 150);
      }
      kit.start(short);
      await kit.untilRound(1, RoundPhase.loading);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      kit.interruptions.add(null);
      await kit.untilRound(1, RoundPhase.interrupted);
      expect(kit.voices.any((v) => v.playing), isFalse);

      for (final v in kit.voices) {
        v.startDelay = const Duration(milliseconds: 1);
      }
      kit.controller.resume();
      await kit.untilRound(1, RoundPhase.answering, attempt: 2);
    });

    test('going to the background pauses the round like a call', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);

      kit.controller.pauseForBackground();
      await kit.untilRound(1, RoundPhase.interrupted);

      expect(kit.voices.any((v) => v.playing), isFalse, reason: 'the clip does not keep playing in the background');
      expect(kit.timers.where((t) => t.duration == const Duration(milliseconds: 10000)).every((t) => !t.isActive), isTrue);

      kit.controller.resume();
      await kit.untilRound(1, RoundPhase.answering, attempt: 2);
    });

    test('going to the background between rounds holds the next round until Resume', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);

      kit.controller.pauseForBackground();
      expect(kit.state.round!.phase, RoundPhase.feedback, reason: 'the answer stays on screen for its second');
      kit.endFeedback();

      await kit.untilRound(2, RoundPhase.interrupted);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(kit.state.round!.phase, RoundPhase.interrupted);
      expect(kit.voices.any((v) => v.playing), isFalse, reason: 'no clip plays while the app is away');
      expect(kit.timers.where((t) => t.isActive && t.duration == const Duration(milliseconds: 10000)), isEmpty);

      kit.controller.resume();
      expect((await kit.untilRound(2, RoundPhase.answering)).remainingMs, 10000);
      expect(kit.voices.any((v) => v.playing), isTrue);
    });

    test('going to the background while a clip loads holds it until Resume', () async {
      for (final v in kit.voices) {
        v.startDelay = const Duration(milliseconds: 150);
      }
      kit.start(short);
      await kit.untilRound(1, RoundPhase.loading);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      kit.controller.pauseForBackground();
      await kit.untilRound(1, RoundPhase.interrupted);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(kit.state.round!.phase, RoundPhase.interrupted);
      expect(kit.voices.any((v) => v.playing), isFalse);

      kit.controller.resume();
      await kit.untilRound(1, RoundPhase.answering);
    });

    test('going to the background before the first round holds it until Resume', () async {
      kit.start(short);
      expect(kit.state.phase, SessionPhase.preparing);
      kit.controller.pauseForBackground();

      await kit.untilRound(1, RoundPhase.interrupted);
      expect(kit.voices.any((v) => v.playing), isFalse);
      kit.controller.resume();
      await kit.untilRound(1, RoundPhase.answering);
    });

    test('a new session does not inherit a pause from the one before', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);
      kit.controller.pauseForBackground();
      kit.controller.leave();

      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
    });

    test('resume does nothing when the round is not interrupted', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.controller.resume();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(kit.state.round!.phase, RoundPhase.answering);
      expect(kit.state.round!.attempt, 1);
    });
  });

  group('leaving', () {
    test('stops the audio and the timers and saves nothing', () async {
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);

      kit.controller.leave();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(kit.state.phase, SessionPhase.idle);
      expect(kit.voices.any((v) => v.playing), isFalse);
      expect(kit.timers.every((t) => !t.isActive), isTrue);
      expect(await kit.db.select(kit.db.pendingSessions).get(), isEmpty);
      expect(kit.state.round, isNull);
    });

    test('during the feedback pause stops the session too', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);

      kit.controller.leave();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(kit.state.phase, SessionPhase.idle);
      expect(await kit.db.select(kit.db.pendingSessions).get(), isEmpty);
    });

    test('while a call has the round paused stops the session', () async {
      kit.start(short);
      await kit.untilRound(1, RoundPhase.answering);
      kit.interruptions.add(null);
      await kit.untilRound(1, RoundPhase.interrupted);

      kit.controller.leave();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(kit.state.phase, SessionPhase.idle);
    });

    test('starting a new session drops the one that was running', () async {
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);

      kit.start(short);
      await kit.playAll(pick: kit.correctOption);

      expect(kit.state.summary!.rounds, hasLength(2));
      final rows = await kit.db.select(kit.db.pendingSessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'session-2');
    });

    test('disposing the controller stops a running session', () async {
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);

      kit.container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(kit.voices.any((v) => v.playing), isFalse);
      expect(kit.timers.every((t) => !t.isActive), isTrue);
    });
  });

  group('preloading', () {
    test('loads the next round while one plays and does not load it again', () async {
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      int loads() => kit.voices.fold(0, (sum, v) => sum + v.loads.length);

      await kit.until(() => loads() == 2, what: 'the next clip to preload');
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);
      kit.endFeedback();
      await kit.untilRound(2, RoundPhase.answering);

      // Round 2 swapped to the preloaded clip. Only round 3 was loaded since.
      await kit.until(() => loads() == 3, what: 'round 3 to preload');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(loads(), 3);
    });
  });
}
