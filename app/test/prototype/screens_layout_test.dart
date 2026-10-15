import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/screen_catalog.dart';
import 'screen_kit.dart';

/// Every screen, in every variant, in both languages at text scale 1.0 and 1.3
/// on a 360 dp wide phone. The only assertion is that nothing overflows or
/// throws: the matching with the approved boards is checked by eye, and kept
/// from drifting by the golden tests in `test/design/`.
void main() {
  setUpAll(loadAppFonts);

  for (final screen in designScreens) {
    for (final locale in languages) {
      for (final scale in textScales) {
        testWidgets(
          '${screen.title} fits, ${locale.languageCode}, text x$scale',
          (tester) async {
            await pumpScreen(
              tester,
              screen.build(),
              locale: locale,
              textScale: scale,
            );
            // Skeletons appear after a short delay; lay them out too.
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
