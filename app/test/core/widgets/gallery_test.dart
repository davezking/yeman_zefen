import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/gallery/component_gallery.dart';

import 'widget_kit.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpGallery(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double scale = 1.0,
  }) async {
    // Tall enough that the list builds every section.
    tester.view.physicalSize = const Size(360, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ComponentGalleryApp(initialLocale: locale, initialTextScale: scale),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final locale in [const Locale('en'), const Locale('am')]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'shows every component without overflow: ${locale.languageCode}, text scale $scale',
        (tester) async {
          await pumpGallery(tester, locale: locale, scale: scale);

          expect(tester.takeException(), isNull);
          expect(find.byType(PrimaryButton), findsWidgets);
          expect(find.byType(SecondaryButton), findsWidgets);
          expect(find.byType(AppIconButton), findsWidgets);
          expect(find.byType(AnswerTile), findsNWidgets(9));
          expect(find.byType(TimerBar), findsNWidgets(3));
          expect(find.byType(PlayingIndicator), findsNWidgets(2));
          expect(find.byType(EraChip), findsNWidgets(6));
          expect(find.byType(EraCard), findsNWidgets(6));
          expect(find.byType(PackCard), findsNWidgets(7));
          expect(find.byType(ScoreBadge), findsNWidgets(2));
          expect(find.byType(ListRow), findsNWidgets(3));
          await tester.pumpWidget(const SizedBox()); // stop the reels
        },
      );
    }
  }

  testWidgets('every answer state and every pack status is on the page', (
    tester,
  ) async {
    await pumpGallery(tester);

    final states = tester
        .widgetList<AnswerTile>(find.byType(AnswerTile))
        .map((t) => t.state)
        .toSet();
    expect(states, AnswerState.values.toSet());
    final statuses = tester
        .widgetList<PackCard>(find.byType(PackCard))
        .map((c) => c.status)
        .toSet();
    expect(statuses, PackStatus.values.toSet());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the language button switches the page to Amharic and the scale button to 1.3',
    (tester) async {
      await pumpGallery(tester);
      expect(find.text('Mahmoud Ahmed'), findsWidgets);
      expect(find.text('ማሕሙድ አሕመድ'), findsNothing);

      await tester.tap(find.text('አማርኛ'));
      await tester.pump();
      expect(find.text('ማሕሙድ አሕመድ'), findsWidgets);

      await tester.tap(find.text('1.0×'));
      await tester.pump();
      expect(find.text('1.3×'), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(ComponentGallery)))
            .scale(10),
        closeTo(13, 0.001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the dialog and bottom sheet buttons open them', (tester) async {
    await pumpGallery(tester);
    // The reels spin forever behind the dialog, so pumpAndSettle would never settle.
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await tester.tap(find.text('Show dialog'));
    await settle();
    expect(find.byType(AppDialog), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await settle();
    expect(find.byType(AppDialog), findsNothing);

    await tester.tap(find.text('Show bottom sheet'));
    await settle();
    expect(find.byType(AppSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
