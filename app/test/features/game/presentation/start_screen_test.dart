import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'screen_kit.dart';

void main() {
  testWidgets('starts with a medium mixed intro game in all eras', (tester) async {
    final h = await pumpScreens(tester, location: '/start');

    await tester.tap(find.text('Start · 10 rounds'));
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
    await tester.tap(find.text("The '90s").last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start · 10 rounds'));
    await tester.pumpAndSettle();

    final started = h.session.startedWith!;
    expect(started.mode, GameMode.middle);
    expect(started.generationId, 3);
    expect(started.difficulty, Difficulty.hard);
    expect(started.questions, QuestionMix.artist);
    expect(h.location, '/play');
  });

  testWidgets('offers every difficulty with its clip length, and all five eras when all are installed', (tester) async {
    await pumpScreens(tester, location: '/start');

    expect(find.text('Easy · 10 s'), findsOneWidget);
    expect(find.text('Medium · 5 s'), findsOneWidget);
    expect(find.text('Hard · 3 s'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    for (final era in ['All eras', 'Golden Age', "The '80s", "The '90s", 'The 2000s', 'Modern']) {
      expect(find.text(era), findsWidgets, reason: era);
    }
  });

  testWidgets('offers only the eras that have installed songs', (tester) async {
    await pumpScreens(tester, location: '/start', eras: {2, 5});
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    for (final era in ['All eras', "The '80s", 'Modern']) {
      expect(find.text(era), findsWidgets, reason: era);
    }
    for (final era in ['Golden Age', "The '90s", 'The 2000s']) {
      expect(find.text(era), findsNothing, reason: era);
    }
  });

  testWidgets('offers only all eras when nothing is installed', (tester) async {
    final h = await pumpScreens(tester, location: '/start', eras: const {});
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    expect(find.text('Golden Age'), findsNothing);
    await tester.tap(find.text('All eras').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start · 10 rounds'));
    await tester.pumpAndSettle();
    expect(h.session.startedWith!.generationId, 0);
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
