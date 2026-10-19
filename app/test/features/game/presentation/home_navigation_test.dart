import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/play_setup.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/prototype/models.dart' as proto;

import 'screen_kit.dart';

void main() {
  testWidgets('Play starts a game with the saved choices and opens the round screen', (tester) async {
    final h = await pumpScreens(tester);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(h.session.startedWith!.mode, GameMode.intro);
    expect(h.session.startedWith!.difficulty, Difficulty.easy);
    expect(h.location, '/play');
  });

  testWidgets('a mode row opens Mode select with that mode chosen', (tester) async {
    final h = await pumpScreens(tester);
    await tester.tap(find.text('Guess from the Middle'));
    await tester.pumpAndSettle();

    expect(h.location, '/mode');
    expect(h.container.read(playSetupProvider).mode, proto.GameMode.middle);
  });

  testWidgets('the leaderboard and settings open from home', (tester) async {
    final h = await pumpScreens(tester);
    await tester.tap(find.text('Leaderboard'));
    await tester.pump();
    expect(h.location, '/leaderboard');

    h.router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump();
    expect(h.location, '/settings');
  });
}
