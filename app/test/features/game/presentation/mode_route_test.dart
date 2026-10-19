import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/play_setup.dart';
import 'package:yeman_zefen/prototype/models.dart' as proto;

import 'screen_kit.dart';

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

  testWidgets('the artist guess is saved from the segmented control', (tester) async {
    final h = await pumpScreens(tester, location: '/mode');
    await tester.tap(find.text('Artist'));
    await tester.pump();
    expect(h.container.read(playSetupProvider).guess, proto.GuessTarget.artist);
  });
}
