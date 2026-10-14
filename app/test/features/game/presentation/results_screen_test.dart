import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'screen_kit.dart';

SessionState finished({
  int total = 412,
  int? bestBefore,
  bool isNewBest = false,
  int skipped = 0,
  bool flagged = false,
  String? saveError,
  SessionConfig sessionConfig = config,
}) {
  return SessionState(
    phase: SessionPhase.finished,
    config: sessionConfig,
    summary: SessionSummary(
      config: sessionConfig,
      totalScore: total,
      rounds: const [
        RoundSummary(
          number: 1, kind: QuestionKind.song, correctLabel: 'ዘፈን\nSong 1', chosenLabel: 'ዘፈን\nSong 1',
          correct: true, points: 206, valid: true, responseMs: 2500,
        ),
        RoundSummary(
          number: 2, kind: QuestionKind.song, correctLabel: 'Song 2', chosenLabel: 'Song 9',
          correct: false, points: 0, valid: true, responseMs: 3100,
        ),
        RoundSummary(
          number: 4, kind: QuestionKind.artist, correctLabel: 'Artist 3', chosenLabel: null,
          correct: false, points: 0, valid: true, responseMs: 10000,
        ),
      ],
      skipped: skipped,
      flagged: flagged,
      bestBefore: bestBefore,
      isNewBest: isNewBest,
      saveError: saveError,
    ),
  );
}

void main() {
  testWidgets('shows the total score and what was played', (tester) async {
    await pumpScreens(
      tester,
      location: '/results',
      state: finished(sessionConfig: const SessionConfig(mode: GameMode.middle, difficulty: Difficulty.hard, generationId: 3)),
    );

    expect(find.text('412'), findsOneWidget);
    expect(find.text('Middle · 1990s · hard'), findsOneWidget);
  });

  testWidgets('lists each round with its points', (tester) async {
    await pumpScreens(tester, location: '/results', state: finished());

    expect(find.byKey(const Key('round-1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('round-1')), matching: find.text('206')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('round-1')), matching: find.text('Correct')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('round-2')), matching: find.text('You chose Song 9')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('round-4')), matching: find.text('Time ran out')), findsOneWidget);
    expect(find.byKey(const Key('round-3')), findsNothing, reason: 'a skipped round is not listed');
  });

  testWidgets('says when the score is a new best', (tester) async {
    await pumpScreens(tester, location: '/results', state: finished(isNewBest: true, bestBefore: 300));
    expect(find.text('New best score!'), findsOneWidget);
    expect(find.byKey(const Key('best')), findsNothing);
  });

  testWidgets('shows the best score when this one did not beat it', (tester) async {
    await pumpScreens(tester, location: '/results', state: finished(bestBefore: 900));
    expect(find.text('Best score: 900'), findsOneWidget);
    expect(find.byKey(const Key('new-best')), findsNothing);
  });

  testWidgets('says how many rounds were skipped', (tester) async {
    await pumpScreens(tester, location: '/results', state: finished(skipped: 1));
    expect(find.textContaining('1 round was skipped'), findsOneWidget);
  });

  testWidgets('uses the plural for several skipped rounds', (tester) async {
    await pumpScreens(tester, location: '/results', state: finished(skipped: 3));
    expect(find.textContaining('3 rounds were skipped'), findsOneWidget);
  });

  testWidgets('shows no notes when nothing went wrong', (tester) async {
    await pumpScreens(tester, location: '/results', state: finished());
    expect(find.byKey(const Key('skipped')), findsNothing);
    expect(find.byKey(const Key('flagged')), findsNothing);
    expect(find.byKey(const Key('save-error')), findsNothing);
  });

  testWidgets('warns about answers that were too fast and about a failed save', (tester) async {
    await pumpScreens(tester, location: '/results', state: finished(flagged: true, saveError: 'disk full'));
    expect(find.text('Some answers were too fast to count.'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  testWidgets('Play again goes to the start screen and Home goes home', (tester) async {
    final h = await pumpScreens(tester, location: '/results', state: finished());

    await tester.scrollUntilVisible(find.text('Play again'), 200);
    await tester.tap(find.text('Play again'));
    await tester.pumpAndSettle();
    expect(h.location, '/start');

    h.router.go('/results');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Home'), 200);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(h.location, '/');
  });

  testWidgets('with nothing to show it offers a new game', (tester) async {
    final h = await pumpScreens(tester, location: '/results');
    expect(find.text('No finished game to show.'), findsOneWidget);

    await tester.tap(find.text('New game'));
    await tester.pumpAndSettle();
    expect(h.location, '/start');
  });
}
