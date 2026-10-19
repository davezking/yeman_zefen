import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/game/presentation/round_route.dart';
import 'package:yeman_zefen/features/settings/application/settings_providers.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';
import 'package:yeman_zefen/prototype/labels.dart';
import 'package:yeman_zefen/prototype/models.dart' as proto;
import 'package:yeman_zefen/core/widgets/widgets.dart';

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

  group('moving between screens', () {
    testWidgets('goes to the results when the session finishes', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));
      expect(h.location, '/play');

      h.session.show(SessionState(
        phase: SessionPhase.finished,
        config: config,
        summary: const SessionSummary(
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
      expect(find.byKey(const Key('total-score')), findsOneWidget);
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
