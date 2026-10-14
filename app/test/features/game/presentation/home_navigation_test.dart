import 'package:flutter_test/flutter_test.dart';

import 'screen_kit.dart';

void main() {
  testWidgets('Play opens the start screen', (tester) async {
    final h = await pumpScreens(tester);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(h.location, '/start');
  });

  testWidgets('Song packs opens the packs screen', (tester) async {
    final h = await pumpScreens(tester);
    await tester.tap(find.text('Song packs'));
    await tester.pump();
    expect(h.location, '/packs');
  });
}
