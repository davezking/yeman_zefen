import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../prototype/screen_kit.dart';
import 'screen_catalog.dart';

/// A picture of every screen and state of the prototype, in `en` and `am`, on
/// two phones (360 x 780 and 430 x 932):
/// `docs/design/flutter/<screen>-<state>-<lang>-<size>.png`.
///
/// They are what the design review compares with the approved boards, and
/// they fail when a screen changes, so the prototype and the screenshots
/// cannot drift apart. After a deliberate change run `tool/export_screens.sh`,
/// which updates them. The goldens are written straight to `docs/`, not to
/// `test/` and then copied: the pictures are big, and one copy is enough.
///
/// The fonts have to be real ones: without them every glyph is a square and
/// Fidel cannot be judged (`loadAppFonts` loads Poppins and Noto Sans Ethiopic
/// from `assets/fonts`).
void main() {
  setUpAll(() async {
    await loadAppFonts();
    goldenFileComparator = LocalFileComparator(
      designScreenshotsDir.resolve('_'),
    );
  });

  for (final screen in designScreens) {
    for (final locale in languages) {
      for (final size in designSizes.entries) {
        final file = '${screen.slug}-${locale.languageCode}-${size.key}.png';
        testWidgets(file, (tester) async {
          await pumpScreen(
            tester,
            screen.build(),
            locale: locale,
            size: size.value,
          );
          // Skeletons appear after a short delay: a fixed time, so the
          // picture is always taken at the same point of an animation.
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
