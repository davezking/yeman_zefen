import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/ads/consent_service.dart';
import 'package:yeman_zefen/core/l10n/display_name.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/game/presentation/results_screen.dart';
import 'package:yeman_zefen/features/game/presentation/round_route.dart';
import 'package:yeman_zefen/features/settings/application/settings_providers.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';
import 'package:yeman_zefen/prototype/labels.dart';
import 'package:yeman_zefen/prototype/models.dart' as proto;
import 'package:yeman_zefen/core/widgets/widgets.dart';

import '../../../core/ads/fake_consent_platform.dart';
import 'screen_kit.dart';

/// The cassette's reels turn for as long as a clip plays, so a playing round never "settles".
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('shows a spinner while the session is being prepared', (tester) async {
    await pumpScreens(tester, location: '/play', state: const SessionState(phase: SessionPhase.preparing, config: config));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Get ready'), findsOneWidget);
  });

  testWidgets('says why a session could not start and goes back', (tester) async {
    final h = await pumpScreens(
      tester,
      location: '/play',
      state: const SessionState(phase: SessionPhase.failed, config: config, error: SessionError(SessionProblem.noSongs)),
    );
    expect(find.text('There are no songs to play yet. Connect to the internet and try again.'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(h.location, '/setup');
  });

  testWidgets('with no game running it offers to start one', (tester) async {
    final h = await pumpScreens(tester, location: '/play');
    expect(find.text('No game is running.'), findsOneWidget);

    await tester.tap(find.text('Start a game'));
    await tester.pumpAndSettle();
    expect(h.location, '/setup');
  });

  testWidgets('shows the loading state, with no options, until the audio is playing', (tester) async {
    await pumpScreens(tester, location: '/play', state: playing(roundView(phase: RoundPhase.loading)));
    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('Song One'), findsNothing);
    expect(find.byType(AnswerTile), findsNothing);
  });

  group('answering', () {
    testWidgets('shows the counter, the running score, the question and four options', (tester) async {
      await pumpScreens(tester, location: '/play', state: playing(roundView(score: 412)));

      expect(find.text('3 / 10'), findsOneWidget);
      expect(find.textContaining('412'), findsOneWidget);
      expect(find.text('Which song is this?'), findsOneWidget);
      expect(find.byType(AnswerTile), findsNWidgets(4));
      for (final name in ['Song One', 'Song Two', 'Song Three', 'Song Four']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byType(TimerBar), findsOneWidget);
    });

    testWidgets('asks who sings it for an artist question, with the singers as options', (tester) async {
      await pumpScreens(tester, location: '/play', state: playing(roundView(kind: QuestionKind.artist)));
      expect(find.text('Who sings this?'), findsOneWidget);
    });

    testWidgets('the cassette turns while the clip plays and stops when it ends', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));
      expect(tester.widget<PlayingIndicator>(find.byType(PlayingIndicator)).playing, isTrue);

      h.session.show(playing(roundView(clipPlaying: false)));
      await tester.pump();
      expect(tester.widget<PlayingIndicator>(find.byType(PlayingIndicator)).playing, isFalse);
    });

    testWidgets('tapping an option sends it to the session', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      await tester.tap(find.text('Song Three'));
      expect(h.session.answered, 13);
    });

    testWidgets('there is no hint button until hints are wired (the ads task)', (tester) async {
      await pumpScreens(tester, location: '/play', state: playing(roundView()));
      expect(find.byIcon(Icons.lightbulb_outline_rounded), findsNothing);
    });
  });

  group('Which Era?', () {
    RoundView eraRound({RoundPhase phase = RoundPhase.answering, int? chosenId, int? correctId}) => RoundView(
          number: 2,
          total: 10,
          kind: QuestionKind.era,
          options: const [
            AnswerOption(id: 1, name: DisplayName()),
            AnswerOption(id: 2, name: DisplayName()),
            AnswerOption(id: 3, name: DisplayName()),
            AnswerOption(id: 5, name: DisplayName()),
          ],
          windowMs: 15000,
          phase: phase,
          attempt: 1,
          chosenId: chosenId,
          correctId: phase == RoundPhase.feedback ? correctId : null,
          points: phase == RoundPhase.feedback ? 0 : null,
          trackName: const DisplayName(latin: 'Song One'),
          artistName: const DisplayName(latin: 'The Singer'),
          clipPlaying: true,
        );

    testWidgets('asks which era, and the options are the eras in the UI language', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(eraRound()));
      expect(find.text('Which era is this song from?'), findsOneWidget);
      expect(find.byType(AnswerTile), findsNWidgets(4));
      expect(find.text('The \'90s'), findsOneWidget);
      expect(find.text('Modern'), findsOneWidget);

      await tester.tap(find.text('Modern'));
      expect(h.session.answered, 5);
    });

    testWidgets('a wrong answer names the song\'s real era', (tester) async {
      await pumpScreens(
        tester,
        location: '/play',
        state: playing(eraRound(phase: RoundPhase.feedback, chosenId: 5, correctId: 3)),
      );
      expect(find.textContaining('The \'90s'), findsWidgets);
      expect(find.text('Your pick'), findsOneWidget);
    });

    testWidgets('the options are named in Amharic too', (tester) async {
      await pumpScreens(tester, location: '/play', state: playing(eraRound()), device: const Locale('am'));
      expect(find.text('ዘመናዊ'), findsOneWidget);
    });
  });

  group('feedback', () {
    testWidgets('a correct answer shows the points and the speed bonus, and marks it correct', (tester) async {
      await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12, points: 206, speedBonus: 56, score: 206)),
      );

      expect(find.textContaining('+206'), findsOneWidget);
      expect(find.text('Speed bonus +56'), findsOneWidget);
      expect(find.text('Correct'), findsWidgets);
    });

    testWidgets('a wrong answer marks the pick, shows the right one and who sang it, and can be skipped', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: playing(
          roundView(phase: RoundPhase.feedback, chosenId: 13, correctId: 12, points: 0, feedbackStartedAtMs: 0, feedbackMs: 5000),
        ),
      );

      expect(find.text('Your pick'), findsOneWidget);
      expect(find.textContaining('Song One · The Singer'), findsOneWidget);
      expect(find.textContaining('Tap to continue'), findsWidgets);

      await tester.tap(find.byType(HeroScaffold));
      expect(h.session.feedbackSkipped, 1);
    });

    testWidgets('running out of time says so and shows the right answer', (tester) async {
      await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, correctId: 12, points: 0, timedOut: true)),
      );
      expect(find.text("Time's up"), findsOneWidget);
    });

    testWidgets('an answer that was too fast says it does not count, instead of Correct', (tester) async {
      await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12, points: 0, valid: false)),
      );
      expect(find.text('Too fast to count. 0 points'), findsOneWidget);
      expect(find.textContaining('Speed bonus'), findsNothing);
    });

    testWidgets('options cannot be tapped during the pause', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12, points: 206)),
      );

      await tester.tap(find.text('Song Four'), warnIfMissed: false);
      expect(h.session.answered, isNull);
    });

    testWidgets('a right answer cannot be skipped by tapping', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12, points: 206)),
      );
      await tester.tap(find.byType(HeroScaffold));
      expect(h.session.feedbackSkipped, 0);
    });
  });

  group('after a call or the app coming back', () {
    testWidgets('shows the paused notice over the stopped timer, and Resume continues', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView(phase: RoundPhase.interrupted)));

      expect(find.text('Paused'), findsWidgets);
      expect(find.textContaining('time you already used still counts'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      expect(h.session.resumed, 1);
    });
  });

  group('going to the background', () {
    testWidgets('pauses the round', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(h.session.backgrounded, 0, reason: 'a notification shade or a system dialog is not leaving the app');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      expect(h.session.backgrounded, greaterThanOrEqualTo(1));
    });

    testWidgets('does nothing when the app comes back', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(h.session.backgrounded, 0);
    });

    testWidgets('is not watched after leaving the round screen', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));
      h.router.go('/setup');
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      expect(h.session.backgrounded, 0);
    });
  });

  group('ads and the hint', () {
    testWidgets('the hint button shows while a rewarded ad is loaded, and opens the sheet', (tester) async {
      // A phone-sized screen, so the button under the answers is on it.
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView(answerClockStartMs: 0)), rewardedReady: true);
      await tester.tap(find.text('Hint'));
      await settle(tester);
      expect(h.session.hintsOpened, 1);
    });

    testWidgets('no hint button without a loaded ad', (tester) async {
      await pumpScreens(tester, location: '/play', state: playing(roundView(answerClockStartMs: 0)));
      expect(find.text('Hint'), findsNothing);
    });

    testWidgets('the sheet: Watch ad and No thanks go to the engine', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(remainingMs: 7000, hintSheetOpenedAtMs: 0)),
        rewardedReady: true,
      );
      await settle(tester);
      expect(find.text('Hint: remove 2 answers'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.text('Watch ad'));
      await tester.tap(find.text('No thanks'));
      expect((h.session.hintAdsWatched, h.session.hintsDeclined), (1, 1));
    });

    testWidgets('a used hint says so, and a hint that did not come is told once', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView(answerClockStartMs: 0)), rewardedReady: true);
      h.session.show(playing(roundView(answerClockStartMs: 0, attempt: 2, hintNotice: HintNotice.notFinished, hintNoticeId: 1)));
      await settle(tester);
      expect(find.text('Watch the whole ad to get the hint.'), findsOneWidget);

      h.session.show(playing(roundView(answerClockStartMs: 0, attempt: 3, hintUsed: true, removedIds: {11, 13}, hintNotice: HintNotice.notFinished, hintNoticeId: 1)));
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(find.text('Watch the whole ad to get the hint.'), findsNothing, reason: 'the same notice is not told again');
      expect(find.text('Hint used · half points'), findsOneWidget);
      expect(find.text('Hint'), findsNothing);
    });

    testWidgets('under a real ad the stand-in shows its caption, with no countdown', (tester) async {
      await pumpScreens(tester, location: '/play', state: playing(roundView(remainingMs: 5000, ad: RoundAd.rewarded)));
      await settle(tester);
      expect(find.text('Your hint is on its way…'), findsOneWidget);
      expect(find.text('Ad'), findsOneWidget);
    });

    testWidgets('where consent is required, the consent screen and Google\'s form come before the results', (tester) async {
      final platform = FakeConsentPlatform()..umpStatus = UmpStatus.required;
      final consent = ConsentService(platform, onAdsAllowed: () async {});
      addTearDown(consent.dispose);
      await consent.startup();
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()), consent: consent);

      h.session.show(SessionState(
        phase: SessionPhase.finished,
        config: config,
        summary: const SessionSummary(
          sessionId: 'test-session',
          config: config,
          totalScore: 1200,
          rounds: [],
          skipped: 0,
          flagged: false,
          bestBefore: null,
          isNewBest: true,
        ),
      ));
      await settle(tester);
      expect(h.location, '/consent');
      expect(find.text('Ads keep this game free'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(platform.calls, contains('form'));
      expect(h.location, '/results');
    });
  });

  group('moving between screens', () {
    testWidgets('goes to the results when the session finishes', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));
      expect(h.location, '/play');

      h.session.show(SessionState(
        phase: SessionPhase.finished,
        config: config,
        summary: const SessionSummary(
          sessionId: 'test-session',
          config: config,
          totalScore: 1200,
          rounds: [],
          skipped: 0,
          flagged: false,
          bestBefore: null,
          isNewBest: true,
        ),
      ));
      await settle(tester);

      expect(h.location, '/results');
      expect(find.byType(ResultsScreen), findsOneWidget);
      // The total counts up from zero on the results screen.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('1,200'), findsWidgets);
    });

    testWidgets('leaving asks first, stops the round under the question, and resumes if the player says no', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      await tester.tap(find.bySemanticsLabel('Leave game'));
      await settle(tester);
      expect(find.text('Leave this game?'), findsOneWidget);
      expect(h.session.backgrounded, 1, reason: 'the round is paused while the question is open');

      await tester.tap(find.text('Keep playing'));
      await settle(tester);
      expect(h.session.left, 0);
      expect(h.session.resumed, 1);
      expect(h.location, '/play');
    });

    testWidgets('a session that ends under the open question waits for the answer', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));
      await tester.tap(find.bySemanticsLabel('Leave game'));
      await settle(tester);

      h.session.show(SessionState(
        phase: SessionPhase.finished,
        config: config,
        summary: const SessionSummary(
          sessionId: 'test-session',
          config: config,
          totalScore: 900,
          rounds: [],
          skipped: 0,
          flagged: false,
          bestBefore: null,
          isNewBest: false,
        ),
      ));
      await settle(tester);
      expect(h.location, '/play', reason: 'the results do not replace the question');

      await tester.tap(find.text('Keep playing'));
      await settle(tester);
      expect(h.location, '/results');
    });

    testWidgets('leaving stops the session and goes to the start screen', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      await tester.tap(find.bySemanticsLabel('Leave game'));
      await settle(tester);
      await tester.tap(find.text('Leave'));
      await settle(tester);

      expect(h.session.left, 1);
      expect(h.location, '/setup');
    });

    testWidgets('the system back button asks first too', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(find.text('Leave this game?'), findsOneWidget);
      expect(h.session.left, 0);
    });

    testWidgets('closing the screen before the first round needs no question either', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: const SessionState(phase: SessionPhase.preparing, config: config),
      );

      await tester.tap(find.byTooltip('Leave game'));
      await settle(tester);

      expect(find.text('Leave this game?'), findsNothing);
      expect(h.session.left, 1);
      expect(h.location, '/setup');
    });

    testWidgets('closing a failed screen needs no question', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: const SessionState(phase: SessionPhase.failed, config: config, error: SessionError(SessionProblem.unexpected, detail: 'x')),
      );

      await tester.tap(find.byTooltip('Leave game'));
      await settle(tester);

      expect(find.text('Leave this game?'), findsNothing);
      expect(h.location, '/setup');
    });
  });

  group('haptics', () {
    final buzzes = <String>[];

    setUp(() {
      buzzes.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') buzzes.add('${call.arguments}');
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('an answer is felt, a wrong one more than a right one', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      h.session.show(playing(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12, points: 100)));
      await tester.pump();
      expect(buzzes, ['HapticFeedbackType.lightImpact']);

      h.session.show(playing(roundView(number: 4, phase: RoundPhase.feedback, chosenId: 13, correctId: 12, points: 0)));
      await tester.pump();
      expect(buzzes.last, 'HapticFeedbackType.heavyImpact');
    });

    testWidgets('are off when the player turned them off', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));
      h.container.read(hapticsOnProvider.notifier).set(false);

      h.session.show(playing(roundView(phase: RoundPhase.feedback, chosenId: 13, correctId: 12, points: 0)));
      await tester.pump();
      expect(buzzes, isEmpty);
    });
  });

  group('what the screen draws for the engine state (screenViewOf)', () {
    late AppLocalizations l10n;

    setUp(() async => l10n = await AppLocalizations.delegate.load(const Locale('en')));

    proto.RoundView view(RoundView round, {int nowMs = 0, bool leaveOpen = false, Locale locale = const Locale('en')}) =>
        screenViewOf(playing(round), l10n: l10n, locale: locale, nowMs: nowMs, leaveOpen: leaveOpen);

    test('the countdown follows the engine\'s clock: a window of 10 s that began at 1000', () {
      final round = roundView(answerClockStartMs: 1000);
      expect(view(round, nowMs: 1000).timeFraction, 1);
      expect(view(round, nowMs: 6000).timeFraction, closeTo(0.5, 0.001));
      expect(view(round, nowMs: 6000).secondsLeft, 5);
      expect(view(round, nowMs: 11000).timeFraction, 0);
      expect(view(round, nowMs: 99999).timeFraction, 0, reason: 'never below empty');
    });

    test('after a pause the clock carries on from the time that was used', () {
      // 4 s were used before the pause, so the clock reads as if it began 4 s before audio resumed.
      final round = roundView(attempt: 2, answerClockStartMs: 3000 - 4000);
      expect(view(round, nowMs: 3000).secondsLeft, 6);
      expect(view(round, nowMs: 5000).secondsLeft, 4);
    });

    test('a paused or interrupted round shows the time that was left, not the clock', () {
      final interrupted = roundView(phase: RoundPhase.interrupted, remainingMs: 4000, answerClockStartMs: 0);
      final v = view(interrupted, nowMs: 50000);
      expect(v.timeFraction, closeTo(0.4, 0.001));
      expect((v.timerPaused, v.overlay), (true, proto.RoundOverlay.paused));

      final open = view(roundView(answerClockStartMs: 0, remainingMs: 7000), nowMs: 2000, leaveOpen: true);
      expect(open.timeFraction, closeTo(0.7, 0.001));
      expect((open.timerPaused, open.overlay), (true, proto.RoundOverlay.leaveDialog));
      expect(open.clipPlaying, isFalse);
    });

    test('feedback: the answered option, the right one, and the seconds left to continue', () {
      final round = roundView(
        phase: RoundPhase.feedback,
        chosenId: 13,
        correctId: 12,
        points: 0,
        remainingMs: 7000,
        feedbackStartedAtMs: 10000,
        feedbackMs: 5000,
      );
      final v = view(round, nowMs: 12500);
      expect((v.phase, v.pickedIndex, v.correctIndex), (proto.RoundPhase.wrong, 2, 1));
      expect(v.feedbackSecondsLeft, 3);
      expect(v.timeFraction, closeTo(0.7, 0.001), reason: 'the bar stays where the answer stopped it');
      expect(view(round, nowMs: 30000).feedbackSecondsLeft, 0);
    });

    test('phases: correct, wrong, timeout', () {
      proto.RoundPhase phaseOf(RoundView r) => view(r).phase;
      expect(phaseOf(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12)), proto.RoundPhase.correct);
      expect(phaseOf(roundView(phase: RoundPhase.feedback, chosenId: 13, correctId: 12)), proto.RoundPhase.wrong);
      expect(phaseOf(roundView(phase: RoundPhase.feedback, correctId: 12, timedOut: true)), proto.RoundPhase.timeout);
    });

    test('the hint sheet: the timer stopped where it opened, and its own countdown', () {
      final round = roundView(remainingMs: 6000, hintSheetOpenedAtMs: 20000);
      final v = view(round, nowMs: 22500);
      expect(v.overlay, proto.RoundOverlay.hintSheet);
      expect(v.overlaySeconds, 6, reason: '8 s sheet, 2.5 s gone');
      expect(v.timerPaused, isTrue);
      expect(v.timeFraction, closeTo(0.6, 0.001));
      expect(view(round, nowMs: 40000).overlaySeconds, 0);
    });

    test('the hint button needs a loaded rewarded ad and a round that offers it', () {
      SessionState state(RoundView r) => playing(r);
      proto.RoundView v(RoundView r, {required bool ready}) =>
          screenViewOf(state(r), l10n: l10n, locale: const Locale('en'), nowMs: 0, rewardedReady: ready);
      expect(v(roundView(answerClockStartMs: 0), ready: true).hintAvailable, isTrue);
      expect(v(roundView(answerClockStartMs: 0), ready: false).hintAvailable, isFalse);
      expect(v(roundView(answerClockStartMs: 0, hintUsed: true), ready: true).hintAvailable, isFalse);
      expect(v(roundView(phase: RoundPhase.loading), ready: true).hintAvailable, isFalse);
    });

    test('a used hint: the removed options by position, and the hint marked used', () {
      final v = view(roundView(answerClockStartMs: 0, hintUsed: true, removedIds: {11, 14}));
      expect(v.removed, {0, 3});
      expect(v.hintUsed, isTrue);
    });

    test('ads cover the round with the timer stopped and the reels still', () {
      final rewarded = view(roundView(remainingMs: 5000, ad: RoundAd.rewarded), nowMs: 99999);
      expect((rewarded.overlay, rewarded.timerPaused, rewarded.clipPlaying), (proto.RoundOverlay.rewardedAd, true, false));
      expect(rewarded.timeFraction, closeTo(0.5, 0.001));
      final interstitial = view(roundView(phase: RoundPhase.feedback, chosenId: 12, ad: RoundAd.interstitial));
      expect(interstitial.overlay, proto.RoundOverlay.interstitial);
      // The leave question and the paused notice come first.
      expect(view(roundView(ad: RoundAd.rewarded), leaveOpen: true).overlay, proto.RoundOverlay.leaveDialog);
    });

    test('names are in the language asked for, so a switch changes the screen at once', () async {
      final am = await AppLocalizations.delegate.load(const Locale('am'));
      final round = roundView(phase: RoundPhase.feedback, chosenId: 13, correctId: 12);
      final english = screenViewOf(playing(round), l10n: l10n, locale: const Locale('en'), nowMs: 0);
      final amharic = screenViewOf(playing(round), l10n: am, locale: const Locale('am'), nowMs: 0);
      expect(l10n.optionLabel(english.options.first, english.kind, const Locale('en')), 'Song One');
      expect(am.optionLabel(amharic.options.first, amharic.kind, const Locale('am')), 'ዘፈን አንድ');
      expect(english.track.title(const Locale('en')), 'Song One');
      expect(amharic.track.artist(const Locale('am')), 'ድምፃዊ');
    });
  });
}
