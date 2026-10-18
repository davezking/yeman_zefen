import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'screen_kit.dart';

void main() {
  Color? background(WidgetTester tester, int optionId) => tester
      .widget<FilledButton>(find.byKey(Key('option-$optionId')))
      .style
      ?.backgroundColor
      ?.resolve({WidgetState.disabled});

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

  testWidgets('shows no options until the audio is playing', (tester) async {
    await pumpScreens(tester, location: '/play', state: playing(roundView(phase: RoundPhase.loading)));
    expect(find.byKey(const Key('option-11')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
  });

  testWidgets('shows 4 options and a countdown once the audio is playing', (tester) async {
    await pumpScreens(tester, location: '/play', state: playing(roundView()));

    expect(find.text('Which song is this?'), findsOneWidget);
    for (final id in [11, 12, 13, 14]) {
      expect(find.byKey(Key('option-$id')), findsOneWidget);
    }
    expect(find.text('Song One'), findsOneWidget);
    expect(find.byKey(const Key('countdown')), findsOneWidget);
    expect(find.byKey(const Key('feedback')), findsNothing);
  });

  testWidgets('the countdown bar empties over the window', (tester) async {
    await pumpScreens(tester, location: '/play', state: playing(roundView()));
    double value() => tester.widget<LinearProgressIndicator>(find.byKey(const Key('countdown'))).value!;

    expect(value(), closeTo(1, 0.01));
    await tester.pump(const Duration(seconds: 5));
    expect(value(), closeTo(0.5, 0.05));
    await tester.pump(const Duration(seconds: 5));
    expect(value(), closeTo(0, 0.05));
  });

  testWidgets('after a pause the bar starts at the time that was left', (tester) async {
    await pumpScreens(tester, location: '/play', state: playing(roundView(attempt: 2, remainingMs: 4000)));
    double value() => tester.widget<LinearProgressIndicator>(find.byKey(const Key('countdown'))).value!;

    expect(value(), closeTo(0.4, 0.01));
    await tester.pump(const Duration(seconds: 2));
    expect(value(), closeTo(0.2, 0.05));
    await tester.pump(const Duration(seconds: 2));
    expect(value(), closeTo(0, 0.05));
  });

  testWidgets('asks who sings it for an artist question', (tester) async {
    await pumpScreens(tester, location: '/play', state: playing(roundView(kind: QuestionKind.artist)));
    expect(find.text('Who sings this?'), findsOneWidget);
  });

  testWidgets('tapping an option sends it to the session', (tester) async {
    final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

    await tester.tap(find.byKey(const Key('option-13')));
    expect(h.session.answered, 13);
  });

  group('feedback', () {
    testWidgets('a correct answer shows the points and marks it green', (tester) async {
      await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12, points: 206)),
      );

      expect(find.text('Correct! +206'), findsOneWidget);
      expect(background(tester, 12), Colors.green);
      expect(find.byKey(const Key('countdown')), findsNothing);
    });

    testWidgets('a wrong answer marks it red and the right one green', (tester) async {
      await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, chosenId: 13, correctId: 12, points: 0)),
      );

      expect(find.text('Not this one'), findsOneWidget);
      expect(background(tester, 13), Colors.red);
      expect(background(tester, 12), Colors.green);
    });

    testWidgets('running out of time says so and shows the right answer', (tester) async {
      await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, correctId: 12, points: 0, timedOut: true)),
      );

      expect(find.text("Time's up"), findsOneWidget);
      expect(background(tester, 12), Colors.green);
    });

    testWidgets('an answer that was too fast says it does not count', (tester) async {
      await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12, points: 0, valid: false)),
      );
      expect(find.text('Too fast to count. 0 points'), findsOneWidget);
    });

    testWidgets('options cannot be tapped during the pause', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView(phase: RoundPhase.feedback, chosenId: 12, correctId: 12, points: 206)),
      );

      await tester.tap(find.byKey(const Key('option-14')), warnIfMissed: false);
      expect(h.session.answered, isNull);
    });
  });

  group('after a call', () {
    testWidgets('offers to resume and hides the options', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView(phase: RoundPhase.interrupted)));

      expect(find.textContaining('Paused'), findsOneWidget);
      expect(find.textContaining('time you already used still counts'), findsOneWidget);
      expect(find.byKey(const Key('option-11')), findsNothing);

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
      await tester.pumpAndSettle();

      expect(h.location, '/results');
      expect(find.byKey(const Key('total-score')), findsOneWidget);
    });

    testWidgets('leaving asks first and keeps playing if the player says no', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      await tester.tap(find.byTooltip('Leave game'));
      await tester.pumpAndSettle();
      expect(find.text('Leave this game?'), findsOneWidget);

      await tester.tap(find.text('Keep playing'));
      await tester.pumpAndSettle();
      expect(h.session.left, 0);
      expect(h.location, '/play');
    });

    testWidgets('leaving stops the session and goes to the start screen', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      await tester.tap(find.byTooltip('Leave game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(h.session.left, 1);
      expect(h.location, '/setup');
    });

    testWidgets('the system back button asks first too', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Leave this game?'), findsOneWidget);
      expect(h.session.left, 0);
    });

    testWidgets('closing a finished or failed screen needs no question', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: const SessionState(phase: SessionPhase.failed, config: config, error: SessionError(SessionProblem.unexpected, detail: 'x')),
      );

      await tester.tap(find.byTooltip('Leave game'));
      await tester.pumpAndSettle();

      expect(find.text('Leave this game?'), findsNothing);
      expect(h.location, '/setup');
    });

    testWidgets('with no game running it offers to start one', (tester) async {
      final h = await pumpScreens(tester, location: '/play');
      expect(find.text('No game is running.'), findsOneWidget);

      await tester.tap(find.text('Start a game'));
      await tester.pumpAndSettle();
      expect(h.location, '/setup');
    });
  });
}
