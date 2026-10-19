import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/play_setup.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/prototype/models.dart' as proto;

import 'screen_kit.dart';

void main() {
  testWidgets('starts a medium song game in all eras, then moves to the round screen', (tester) async {
    final h = await pumpScreens(tester, location: '/setup');

    await tester.tap(find.text('Start · 10 rounds'));
    await tester.pumpAndSettle();

    final started = h.session.startedWith!;
    expect(started.mode, GameMode.intro);
    expect(started.generationId, 0);
    expect(started.difficulty, Difficulty.easy);
    expect(started.questions, QuestionMix.song);
    expect(started.rounds, 10);
    expect(h.location, '/play');
  });

  testWidgets('starts the chosen era, difficulty and question kind', (tester) async {
    final h = await pumpScreens(tester, location: '/setup');
    h.container.read(playSetupProvider.notifier).choose(
          const proto.PlaySettings(
            generationId: 3,
            mode: proto.GameMode.middle,
            guess: proto.GuessTarget.artist,
            difficulty: proto.Difficulty.hard,
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start · 10 rounds'));
    await tester.pumpAndSettle();

    final started = h.session.startedWith!;
    expect(started.mode, GameMode.middle);
    expect(started.generationId, 3);
    expect(started.difficulty, Difficulty.hard);
    expect(started.questions, QuestionMix.artist);
  });

  testWidgets('a chosen era with too few playable songs starts all eras instead', (tester) async {
    final h = await pumpScreens(tester, location: '/setup', eras: {2, 5});
    h.container.read(playSetupProvider.notifier).choose(
          const proto.PlaySettings(generationId: 3),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start · 10 rounds'));
    await tester.pumpAndSettle();

    expect(h.session.startedWith!.generationId, 0);
  });

  testWidgets('with too few songs in all eras, Start does nothing', (tester) async {
    final h = await pumpScreens(tester, location: '/setup', eras: const {});
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start · 10 rounds'));
    await tester.pumpAndSettle();

    expect(h.session.startedWith, isNull);
    expect(h.location, '/setup');
  });
}
