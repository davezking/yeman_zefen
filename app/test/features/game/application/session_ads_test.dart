import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/ads/ad_service.dart';
import 'package:yeman_zefen/core/config/remote_config.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/data/session_store.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'session_kit.dart';

// Medium: a 5 s clip and a 10 s window. A right answer at 2500 ms scores 150 + 56 = 206, at 3500 ms 150 + 49 = 199.
const song = SessionConfig(mode: GameMode.intro, difficulty: Difficulty.medium, questions: QuestionMix.song);
const windowMs = 10000;
const sheetMs = 8000;

void main() {
  late SessionKit kit;

  setUp(() async {
    kit = await SessionKit.create();
  });

  tearDown(() => kit.dispose());

  Future<Map<String, dynamic>> savedPayload() async {
    final row = await kit.db.select(kit.db.pendingSessions).getSingle();
    return jsonDecode(row.payloadJson) as Map<String, dynamic>;
  }

  /// The player has finished a session before, so this is not their first.
  Future<void> notFirstSession() => kit.db.into(kit.db.localCounters).insert(
    LocalCountersCompanion.insert(name: SessionStore.completedSessionsCounter, count: const Value(1)),
  );

  bool clipPlaying() => kit.voices.any((v) => v.playing);

  FakeTimer sheetTimer() => kit.timers.lastWhere((t) => t.isActive && t.duration == const Duration(milliseconds: sheetMs));

  bool windowRunning() => kit.timers.any((t) => t.isActive && t.duration.inMilliseconds <= windowMs && t.duration != SessionKit.feedback && t.duration != const Duration(milliseconds: sheetMs));

  group('the hint', () {
    test('is offered only while a rewarded ad is loaded', () async {
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.controller.openHint();
      expect(kit.state.round!.hintSheetOpenedAtMs, isNull, reason: 'no ad is loaded');

      kit.ads.rewarded.value = true;
      expect(kit.state.round!.hintOffered, isTrue);
      kit.controller.openHint();
      expect(kit.state.round!.hintSheetOpenedAtMs, isNotNull);
    });

    test('a watched ad removes two wrong options, halves the points and reports the reward', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      final correct = kit.correctOption();

      kit.clockMs += 3000;
      kit.controller.openHint();
      final open = kit.state.round!;
      expect(open.hintSheetOpenedAtMs, kit.clockMs);
      expect(open.answerClockStartMs, isNull, reason: 'the answer clock is stopped');
      expect(open.remainingMs, windowMs - 3000);
      expect(clipPlaying(), isTrue, reason: 'the clip keeps playing while the sheet is open');

      // Time on the sheet does not count.
      kit.clockMs += 4000;
      kit.controller.watchHintAd();
      await kit.until(() => kit.ads.rewardedShowing, what: 'the rewarded ad');
      expect(kit.state.ad, RoundAd.rewarded);
      expect(clipPlaying(), isFalse, reason: 'the clip stops for the ad');

      // Nor does the time the ad plays, and the app leaving for the ad is not a pause.
      kit.clockMs += 30000;
      kit.controller.pauseForBackground();
      kit.ads.closeRewarded(RewardedResult.earned);

      final round = await kit.untilRound(1, RoundPhase.answering, attempt: 2);
      expect(round.hintUsed, isTrue);
      expect(round.removedIds, hasLength(2));
      expect(round.removedIds, isNot(contains(correct)));
      expect(round.remainingMs, windowMs - 3000, reason: 'the window carries on from where the sheet opened');
      expect(round.hintOffered, isFalse, reason: 'one hint a round');

      // A removed option cannot be picked.
      kit.controller.answer(round.removedIds.first);
      expect(kit.state.round!.phase, RoundPhase.answering);

      kit.clockMs += 500;
      kit.controller.answer(correct);
      final feedback = await kit.untilRound(1, RoundPhase.feedback);
      // 3000 + 500 ms: 150 + 49 = 199 points, halved (half up) to 100.
      expect(feedback.points, 100);
      expect(feedback.hintUsed, isTrue);
      kit.endFeedback();

      await kit.playAll(pick: kit.correctOption);
      expect(kit.state.summary!.rounds.first.points, 100);
      final payload = await savedPayload();
      final first = (payload['rounds'] as List).first as Map<String, dynamic>;
      expect(first['hintUsed'], isTrue);
      expect(first['responseMs'], 3500);
      expect((payload['rounds'] as List).skip(1).every((r) => (r as Map)['hintUsed'] == false), isTrue);
      expect(payload['ads'], {'interstitialShown': 0, 'rewardedCompleted': 1});
    });

    test('in a build without ads the hint is given at once, with no sheet and no ad', () async {
      kit.ads.hints = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      final correct = kit.correctOption();
      expect(kit.state.round!.hintOffered, isTrue);

      kit.clockMs += 3000;
      kit.controller.openHint();
      final round = kit.state.round!;
      expect(round.hintSheetOpenedAtMs, isNull, reason: 'no sheet');
      expect(kit.ads.rewardedShows, 0, reason: 'no ad');
      expect(round.answerClockStartMs, isNotNull, reason: 'the answer clock keeps running');
      expect(round.hintUsed, isTrue);
      expect(round.removedIds, hasLength(2));
      expect(round.removedIds, isNot(contains(correct)));
      expect(round.hintOffered, isFalse, reason: 'one hint a round');

      kit.clockMs += 500;
      kit.controller.answer(correct);
      // 3000 + 500 ms: 150 + 49 = 199 points, halved (half up) to 100.
      expect((await kit.untilRound(1, RoundPhase.feedback)).points, 100);
      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);
      final payload = await savedPayload();
      expect(((payload['rounds'] as List).first as Map)['hintUsed'], isTrue);
      expect(payload['ads'], {'interstitialShown': 0, 'rewardedCompleted': 0});
    });

    test('an ad closed early changes nothing and tells the player', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2000;
      kit.controller.openHint();
      kit.controller.watchHintAd();
      await kit.until(() => kit.ads.rewardedShowing, what: 'the rewarded ad');
      kit.ads.closeRewarded(RewardedResult.notFinished);

      final round = await kit.untilRound(1, RoundPhase.answering, attempt: 2);
      expect(round.hintUsed, isFalse);
      expect(round.removedIds, isEmpty);
      expect(round.hintNotice, HintNotice.notFinished);
      expect(round.remainingMs, windowMs - 2000);
      kit.ads.rewarded.value = true;
      expect(round.hintOffered, isFalse, reason: 'one try a round, even without the reward');

      kit.clockMs += 500;
      kit.controller.answer(kit.correctOption());
      expect((await kit.untilRound(1, RoundPhase.feedback)).points, 206);
      kit.endFeedback();
      await kit.playAll(pick: kit.correctOption);
      final payload = await savedPayload();
      expect(((payload['rounds'] as List).first as Map)['hintUsed'], isFalse);
      expect(payload['ads'], {'interstitialShown': 0, 'rewardedCompleted': 0});
    });

    test('an ad that cannot show says so', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.controller.openHint();
      // The ad went away while the sheet was open.
      kit.ads.rewarded.value = false;
      kit.controller.watchHintAd();
      final round = kit.state.round!;
      expect(round.hintNotice, HintNotice.unavailable);
      expect(round.hintSheetOpenedAtMs, isNull);
      expect(round.answerClockStartMs, isNotNull, reason: 'the clock runs again');
      expect(kit.ads.rewardedShows, 0);
    });

    test('"No thanks" restarts the window with what was left, and answers wait while the sheet is open', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      final correct = kit.correctOption();
      kit.clockMs += 3000;
      kit.controller.openHint();
      expect(windowRunning(), isFalse);

      kit.controller.answer(correct);
      expect(kit.state.round!.phase, RoundPhase.answering, reason: 'the sheet covers the answers');

      kit.clockMs += 5000;
      kit.controller.declineHint();
      final round = kit.state.round!;
      expect(round.hintSheetOpenedAtMs, isNull);
      expect(kit.clockMs - round.answerClockStartMs!, 3000, reason: 'the sheet time is not counted');
      expect(kit.timers.where((t) => t.isActive && t.duration == const Duration(milliseconds: windowMs - 3000)), hasLength(1));

      kit.clockMs += 500;
      kit.controller.answer(correct);
      final feedback = await kit.untilRound(1, RoundPhase.feedback);
      expect(feedback.points, 150 + 49, reason: '3500 ms, no hint');
    });

    test('the sheet opens once a round: "No thanks" cannot be used to stop the clock again', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 1000;
      kit.controller.openHint();
      kit.clockMs += 4000;
      kit.controller.declineHint();
      expect(kit.state.round!.hintOffered, isFalse);

      kit.clockMs += 1000;
      kit.controller.openHint();
      final round = kit.state.round!;
      expect(round.hintSheetOpenedAtMs, isNull);
      expect(kit.clockMs - round.answerClockStartMs!, 2000, reason: 'the clock keeps running');
    });

    test('leaving while the rewarded ad is up does not leave the next session blocked', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.controller.openHint();
      kit.controller.watchHintAd();
      await kit.until(() => kit.ads.rewardedShowing, what: 'the rewarded ad');
      // The ad never reports closing; the player leaves and starts again.
      kit.controller.leave();
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2500;
      kit.controller.answer(kit.correctOption());
      expect((await kit.untilRound(1, RoundPhase.feedback)).points, 206);

      // The old ad closing late changes nothing in the new session.
      kit.ads.closeRewarded(RewardedResult.earned);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(kit.state.round!.hintUsed, isFalse);
    });

    test('an ad that never reports closing is given up after its time limit', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2000;
      kit.controller.openHint();
      kit.controller.watchHintAd();
      await kit.until(() => kit.ads.rewardedShowing, what: 'the rewarded ad');
      kit.timers.lastWhere((t) => t.isActive && t.duration == const Duration(minutes: 3)).fire();

      final round = await kit.untilRound(1, RoundPhase.answering, attempt: 2);
      expect(round.hintNotice, HintNotice.unavailable);
      expect(kit.state.ad, RoundAd.none);
      kit.clockMs += 500;
      kit.controller.answer(kit.correctOption());
      await kit.untilRound(1, RoundPhase.feedback);
    });

    test('if the app is still away when the ad closes, the clip waits for Resume', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2000;
      kit.controller.openHint();
      kit.controller.watchHintAd();
      await kit.until(() => kit.ads.rewardedShowing, what: 'the rewarded ad');
      // A call came in while the ad played.
      kit.foreground = false;
      kit.ads.closeRewarded(RewardedResult.earned);
      await kit.until(() => kit.timers.any((t) => t.isActive && t.duration == const Duration(milliseconds: 1500)), what: 'the wait');
      kit.timers.lastWhere((t) => t.isActive && t.duration == const Duration(milliseconds: 1500)).fire();

      final round = await kit.untilRound(1, RoundPhase.interrupted);
      expect(round.remainingMs, windowMs - 2000);
      expect(round.hintUsed, isTrue);
      kit.foreground = true;
      kit.controller.resume();
      final resumed = await kit.untilRound(1, RoundPhase.answering, attempt: 2);
      expect(resumed.removedIds, hasLength(2));
    });

    test('an app back in front within the wait plays on', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.controller.openHint();
      kit.controller.watchHintAd();
      await kit.until(() => kit.ads.rewardedShowing, what: 'the rewarded ad');
      kit.foreground = false;
      kit.ads.closeRewarded(RewardedResult.notFinished);
      await kit.until(() => kit.timers.any((t) => t.isActive && t.duration == const Duration(milliseconds: 1500)), what: 'the wait');
      kit.foreground = true;
      kit.timers.lastWhere((t) => t.isActive && t.duration == const Duration(milliseconds: 1500)).fire();
      await kit.untilRound(1, RoundPhase.answering, attempt: 2);
    });

    test('the sheet closes by itself after 8 s', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 1000;
      kit.controller.openHint();
      kit.clockMs += sheetMs;
      sheetTimer().fire();
      final round = kit.state.round!;
      expect(round.hintSheetOpenedAtMs, isNull);
      expect(kit.clockMs - round.answerClockStartMs!, 1000);
    });

    test('the app going to the background with the sheet open pauses at the time the sheet opened', () async {
      kit.ads.rewarded.value = true;
      kit.start(song);
      await kit.untilRound(1, RoundPhase.answering);
      kit.clockMs += 2000;
      kit.controller.openHint();
      kit.clockMs += 3000;
      kit.controller.pauseForBackground();
      final round = await kit.untilRound(1, RoundPhase.interrupted);
      expect(round.remainingMs, windowMs - 2000);
      expect(round.hintSheetOpenedAtMs, isNull);
      expect(kit.timers.where((t) => t.isActive && t.duration == const Duration(milliseconds: sheetMs)), isEmpty);
    });
  });

  group('interstitials', () {
    test('never show in the first session', () async {
      kit.ads.interstitialLoaded = true;
      kit.start(song);
      await kit.playAll(pick: kit.correctOption);
      expect(kit.ads.interstitialShows, 0);
      expect((await savedPayload())['ads'], {'interstitialShown': 0, 'rewardedCompleted': 0});
    });

    test('show every 3 rounds between rounds, never after the last, and are counted', () async {
      await notFirstSession();
      kit.ads.interstitialLoaded = true;
      kit.start(song);
      final shownAfter = <int>[];
      var last = 0;
      while (true) {
        await kit.until(
          () =>
              kit.state.phase == SessionPhase.finished ||
              kit.ads.interstitialShowing ||
              (kit.state.round?.phase == RoundPhase.answering && kit.state.round!.number > last),
          what: 'the next step',
        );
        if (kit.state.phase == SessionPhase.finished) break;
        if (kit.ads.interstitialShowing) {
          final round = kit.state.round!;
          expect(kit.state.ad, RoundAd.interstitial);
          expect(round.phase, RoundPhase.feedback, reason: 'after the feedback');
          expect(clipPlaying(), isFalse, reason: 'never while audio plays');
          shownAfter.add(round.number);
          // The app leaving for the ad is not a pause: the next round plays straight after it.
          kit.controller.pauseForBackground();
          kit.ads.closeInterstitial();
          await kit.untilRound(round.number + 1, RoundPhase.answering);
          continue;
        }
        last = kit.state.round!.number;
        kit.clockMs += 2500;
        kit.controller.answer(kit.correctOption());
        await kit.untilRound(last, RoundPhase.feedback);
        kit.endFeedback();
      }
      expect(shownAfter, [3, 6, 9]);
      expect((await savedPayload())['ads'], {'interstitialShown': 3, 'rewardedCompleted': 0});
    });

    test('follow interstitialEveryRounds from the config, and wait for an ad to be loaded', () async {
      await notFirstSession();
      kit.container.read(remoteConfigProvider.notifier).replace(
        RemoteConfig(
          interstitialEveryRounds: 4,
          registerPromptAfterSessions: RemoteConfig.defaults.registerPromptAfterSessions,
          registerPromptCooldownDays: RemoteConfig.defaults.registerPromptCooldownDays,
          minAppVersion: RemoteConfig.defaults.minAppVersion,
          defaultClipMs: RemoteConfig.defaults.defaultClipMs,
        ),
      );
      kit.ads.reloadInterstitial = false;
      kit.start(song);
      final shownAfter = <int>[];
      var last = 0;
      while (true) {
        await kit.until(
          () =>
              kit.state.phase == SessionPhase.finished ||
              kit.ads.interstitialShowing ||
              (kit.state.round?.phase == RoundPhase.answering && kit.state.round!.number > last),
          what: 'the next step',
        );
        if (kit.state.phase == SessionPhase.finished) break;
        if (kit.ads.interstitialShowing) {
          shownAfter.add(kit.state.round!.number);
          kit.ads.closeInterstitial();
          continue;
        }
        last = kit.state.round!.number;
        // No ad is loaded until round 6: the one due after round 4 waits for it.
        if (last == 6) kit.ads.interstitialLoaded = true;
        kit.clockMs += 2500;
        kit.controller.answer(kit.correctOption());
        await kit.untilRound(last, RoundPhase.feedback);
        kit.endFeedback();
      }
      expect(shownAfter, [6]);
    });

    test('do not show while the player is being asked to leave', () async {
      await notFirstSession();
      kit.ads.interstitialLoaded = true;
      kit.start(song);
      for (var n = 1; n <= 3; n++) {
        await kit.untilRound(n, RoundPhase.answering);
        kit.clockMs += 2500;
        kit.controller.answer(kit.correctOption());
        await kit.untilRound(n, RoundPhase.feedback);
        // "Leave this game?" opens during the third round's feedback.
        if (n == 3) kit.controller.pauseForBackground();
        kit.endFeedback();
      }
      await kit.untilRound(4, RoundPhase.interrupted);
      expect(kit.ads.interstitialShows, 0);
    });
  });
}
