import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/play_setup.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart' as domain;
import 'package:yeman_zefen/prototype/models.dart' as proto;

import 'screen_kit.dart';

/// Saves new Play choices, as the screens do.
void updateSetup(Harness h, proto.PlaySettings settings) =>
    h.container.read(playSetupProvider.notifier).choose(settings);

void main() {
  testWidgets('a mode card saves the mode, and Next opens setup', (tester) async {
    final h = await pumpScreens(tester, location: '/mode');

    await tester.tap(find.text('Guess from the Middle'));
    await tester.pump();
    expect(h.container.read(playSetupProvider).mode, proto.GameMode.middle);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(h.location, '/setup');
  });

  testWidgets('all three modes are offered, and Which Era? hides the question choice', (tester) async {
    final h = await pumpScreens(tester, location: '/mode');
    expect(find.text('Guess the Intro'), findsOneWidget);
    expect(find.text('Guess from the Middle'), findsOneWidget);
    expect(find.text('Which Era?'), findsOneWidget);
    expect(find.text('Guess the'), findsOneWidget);

    await tester.tap(find.text('Which Era?'));
    await tester.pump();
    expect(h.container.read(playSetupProvider).mode, proto.GameMode.era);
    expect(find.text('Guess the'), findsNothing, reason: 'every round asks for the era');
  });

  testWidgets('Mixed asks song and artist questions, and is saved', (tester) async {
    final h = await pumpScreens(tester, location: '/mode');
    await tester.tap(find.text('Mixed'));
    await tester.pump();
    expect(h.container.read(playSetupProvider).guess, proto.GuessTarget.mixed);
  });

  testWidgets('Home offers Which Era? as a way to play', (tester) async {
    await pumpScreens(tester);
    expect(find.text('Which Era?'), findsWidgets);
  });

  testWidgets('Home looks up the Which Era? best under all eras, where its sessions are saved', (tester) async {
    final asked = <(domain.GameMode, int)>[];
    final h = await pumpScreens(tester, bestScore: (mode, era) async {
      asked.add((mode, era));
      return null;
    });
    updateSetup(h, const proto.PlaySettings(mode: proto.GameMode.era, generationId: 3));
    await tester.pump();
    await tester.pump();
    expect(asked.last, (domain.GameMode.generation, 0));
  });

  testWidgets('the artist guess is saved from the segmented control', (tester) async {
    final h = await pumpScreens(tester, location: '/mode');
    await tester.tap(find.text('Artist'));
    await tester.pump();
    expect(h.container.read(playSetupProvider).guess, proto.GuessTarget.artist);
  });
}
