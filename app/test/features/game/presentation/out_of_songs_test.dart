import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';

import 'screen_kit.dart';

/// Offline, with every song on the phone played recently: the round screen shows the designed note
/// before the game, and the player picks repeats or more songs.
void main() {
  const outOfSongs = SessionState(phase: SessionPhase.outOfSongs, config: config);

  testWidgets('says why, and "Play them again" goes on with the repeats', (tester) async {
    final h = await pumpScreens(tester, location: '/play', state: outOfSongs);
    await tester.pumpAndSettle();

    expect(find.text("You've played every song here"), findsOneWidget);
    await tester.tap(find.text('Play them again'));
    await tester.pump();
    expect(h.session.replayed, 1);
    expect(h.session.left, 0);
  });

  testWidgets('"Browse packs" leaves the game for Offline play', (tester) async {
    final h = await pumpScreens(tester, location: '/play', state: outOfSongs);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Browse packs'));
    await tester.pumpAndSettle();
    expect(h.session.left, 1);
    expect(h.router.routerDelegate.currentConfiguration.uri.path, '/packs');
  });
}
