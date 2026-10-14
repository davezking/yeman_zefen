import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'screen_kit.dart';

void main() {
  testWidgets('starts with a medium mixed intro game in all eras', (tester) async {
    final h = await pumpScreens(tester, location: '/start');

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    final started = h.session.startedWith!;
    expect(started.mode, GameMode.intro);
    expect(started.generationId, 0);
    expect(started.difficulty, Difficulty.medium);
    expect(started.questions, QuestionMix.mixed);
    expect(started.rounds, 10);
  });

  testWidgets('starts the game that was picked and moves to the round screen', (tester) async {
    final h = await pumpScreens(tester, location: '/start');

    await tester.tap(find.text('Middle'));
    await tester.tap(find.text('Hard · 3 s'));
    await tester.tap(find.text('Artist'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1990s').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    final started = h.session.startedWith!;
    expect(started.mode, GameMode.middle);
    expect(started.generationId, 3);
    expect(started.difficulty, Difficulty.hard);
    expect(started.questions, QuestionMix.artist);
    expect(h.location, '/play');
  });

  testWidgets('offers every difficulty with its clip length, and all five eras', (tester) async {
    await pumpScreens(tester, location: '/start');

    expect(find.text('Easy · 10 s'), findsOneWidget);
    expect(find.text('Medium · 5 s'), findsOneWidget);
    expect(find.text('Hard · 3 s'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    for (final era in ['All eras', 'Golden Age', '1980s', '1990s', '2000s', 'Modern']) {
      expect(find.text(era), findsWidgets, reason: era);
    }
  });

  testWidgets('shows the best score for the chosen mode and era', (tester) async {
    await pumpScreens(
      tester,
      location: '/start',
      bestScore: (mode, era) async => mode == GameMode.intro && era == 0 ? 900 : null,
    );
    await tester.pump();
    expect(find.text('Best score: 900'), findsOneWidget);

    await tester.tap(find.text('Middle'));
    await tester.pumpAndSettle();
    expect(find.text('No best score yet for this mode and era.'), findsOneWidget);
  });
}
