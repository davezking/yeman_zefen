import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/theme/tokens.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';

import 'widget_kit.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpTile(
    WidgetTester tester,
    Widget tile, {
    bool disableAnimations = false,
  }) => pumpComponent(tester, tile, disableAnimations: disableAnimations);

  group('AnswerTile', () {
    testWidgets(
      'an idle tile can be tapped and is at least the design height',
      (tester) async {
        var taps = 0;
        await pumpTile(
          tester,
          AnswerTile(text: 'Aster Aweke', onTap: () => taps++),
        );

        await tester.tap(find.text('Aster Aweke'));
        expect(taps, 1);
        expect(
          tester.getSize(find.byType(AnswerTile)).height,
          greaterThanOrEqualTo(SizeTokens.answerTileMinHeight),
        );
      },
    );

    testWidgets('only an idle tile reacts to a tap', (tester) async {
      var taps = 0;
      for (final state in [
        AnswerState.selected,
        AnswerState.correct,
        AnswerState.wrong,
        AnswerState.disabled,
        AnswerState.removed,
      ]) {
        await pumpTile(
          tester,
          AnswerTile(text: 'Aster Aweke', state: state, onTap: () => taps++),
          disableAnimations: true,
        );
        await tester.tap(find.text('Aster Aweke'), warnIfMissed: false);
        await tester.pump();
      }
      expect(taps, 0);
    });

    testWidgets('correct shows a check and its word, not just a color', (
      tester,
    ) async {
      await pumpTile(
        tester,
        const AnswerTile(
          text: 'Aster Aweke',
          state: AnswerState.correct,
          stateLabel: 'Correct',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('Correct'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('wrong shows an X and its word', (tester) async {
      await pumpTile(
        tester,
        const AnswerTile(
          text: 'Aster Aweke',
          state: AnswerState.wrong,
          stateLabel: 'Your pick',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('Your pick'), findsOneWidget);
    });

    testWidgets('the icon is there even if the caller forgot the word', (
      tester,
    ) async {
      await pumpTile(
        tester,
        const AnswerTile(text: 'Aster Aweke', state: AnswerState.wrong),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('correct and wrong are painted differently', (tester) async {
      Gradient? gradientOf() {
        final box = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(AnswerTile),
                matching: find.byType(DecoratedBox),
              ),
            )
            .first;
        return (box.decoration as BoxDecoration).gradient;
      }

      await pumpTile(
        tester,
        const AnswerTile(text: 'A', state: AnswerState.correct),
      );
      final correct = gradientOf();
      await pumpTile(
        tester,
        const AnswerTile(text: 'A', state: AnswerState.wrong),
      );
      await tester.pumpAndSettle();
      expect(gradientOf(), isNot(correct));
      expect((correct as LinearGradient).colors.last, ColorTokens.correctFill);
    });

    testWidgets(
      'disabled is faded, removed is fainter, and removed has no shadow',
      (tester) async {
        await pumpTile(
          tester,
          const AnswerTile(text: 'A', state: AnswerState.disabled),
        );
        expect(
          tester
              .widget<Opacity>(
                find.descendant(
                  of: find.byType(AnswerTile),
                  matching: find.byType(Opacity),
                ),
              )
              .opacity,
          ColorTokens.answerDimOpacity,
        );

        await pumpTile(
          tester,
          const AnswerTile(text: 'A', state: AnswerState.removed),
        );
        expect(
          tester
              .widget<Opacity>(
                find.descendant(
                  of: find.byType(AnswerTile),
                  matching: find.byType(Opacity),
                ),
              )
              .opacity,
          ColorTokens.answerRemovedOpacity,
        );
        final box = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(AnswerTile),
                matching: find.byType(DecoratedBox),
              ),
            )
            .first;
        expect((box.decoration as BoxDecoration).boxShadow, isEmpty);
      },
    );

    testWidgets(
      'a removed tile is not announced; an idle one is read as one button with its label',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpTile(
          tester,
          const AnswerTile(
            text: 'Aster Aweke',
            state: AnswerState.removed,
            semanticLabel: 'Answer 3: Aster Aweke',
          ),
        );
        expect(find.bySemanticsLabel('Answer 3: Aster Aweke'), findsNothing);

        var taps = 0;
        await pumpTile(
          tester,
          AnswerTile(
            text: 'Aster Aweke',
            semanticLabel: 'Answer 3: Aster Aweke',
            onTap: () => taps++,
          ),
        );
        expect(find.bySemanticsLabel('Answer 3: Aster Aweke'), findsOneWidget);
        // A screen reader user can activate it, not just hear it.
        tester.semantics.tap(find.semantics.byLabel('Answer 3: Aster Aweke'));
        expect(taps, 1);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Answer 3: Aster Aweke')),
          matchesSemantics(
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
            label: 'Answer 3: Aster Aweke',
          ),
        );
        handle.dispose();
      },
    );

    testWidgets('the revealed state is announced with its word', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpTile(
        tester,
        const AnswerTile(
          text: 'Aster Aweke',
          state: AnswerState.correct,
          stateLabel: 'Correct',
          semanticLabel: 'Answer 3: Aster Aweke',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Answer 3: Aster Aweke, Correct'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the reveal pops, unless the system asked for reduced motion', (
      tester,
    ) async {
      final pop = find.descendant(
        of: find.byType(AnswerTile),
        matching: find.byType(ScaleTransition),
      );

      await pumpTile(
        tester,
        const AnswerTile(text: 'A', state: AnswerState.correct),
      );
      expect(pop, findsOneWidget);
      await tester.pumpAndSettle();

      await pumpTile(
        tester,
        const AnswerTile(text: 'A', state: AnswerState.correct),
        disableAnimations: true,
      );
      expect(pop, findsNothing);
    });

    testWidgets(
      'rebuilding a revealed tile reuses its pop animation instead of making a new one',
      (tester) async {
        // A new animation per build would add a listener to the controller on every
        // rebuild, and the round rebuilds every 100 ms.
        late StateSetter set;
        await pumpTile(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return const AnswerTile(text: 'A', state: AnswerState.correct);
            },
          ),
        );
        final pop = find.descendant(
          of: find.byType(AnswerTile),
          matching: find.byType(ScaleTransition),
        );
        final first = tester.widget<ScaleTransition>(pop).scale;
        set(() {});
        await tester.pump();
        expect(
          identical(tester.widget<ScaleTransition>(pop).scale, first),
          isTrue,
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets('going from idle to correct plays the pop', (tester) async {
      final pop = find.descendant(
        of: find.byType(AnswerTile),
        matching: find.byType(ScaleTransition),
      );
      var state = AnswerState.idle;
      late StateSetter set;
      await pumpTile(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return AnswerTile(text: 'A', state: state, stateLabel: 'Correct');
          },
        ),
      );
      expect(pop, findsNothing);

      set(() => state = AnswerState.correct);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final scale = tester.widget<ScaleTransition>(pop).scale.value;
      expect(scale, isNot(1.0)); // mid-pop
      await tester.pumpAndSettle();
      expect(tester.widget<ScaleTransition>(pop).scale.value, 1.0);
    });
  });

  group('EqualHeightGrid', () {
    testWidgets(
      'two answers side by side are the same height, even when one is much longer',
      (tester) async {
        await pumpComponent(
          tester,
          EqualHeightGrid(
            children: [
              AnswerTile(text: 'Aster', onTap: () {}),
              AnswerTile(
                text: 'A very long artist name that takes several lines to read at this width',
                onTap: () {},
              ),
              AnswerTile(text: 'Short', onTap: () {}),
              AnswerTile(text: 'Short too', onTap: () {}),
            ],
          ),
          textScale: 1.3,
        );

        final tiles = find.byType(AnswerTile);
        expect(
          tester.getSize(tiles.at(0)).height,
          tester.getSize(tiles.at(1)).height,
        );
        expect(
          tester.getSize(tiles.at(2)).height,
          tester.getSize(tiles.at(3)).height,
        );
        expect(
          tester.getSize(tiles.at(1)).height,
          greaterThan(tester.getSize(tiles.at(2)).height),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('an odd last cell keeps the column width', (tester) async {
      await pumpComponent(
        tester,
        EqualHeightGrid(
          children: [
            AnswerTile(text: 'A', onTap: () {}),
            AnswerTile(text: 'B', onTap: () {}),
            AnswerTile(text: 'C', onTap: () {}),
          ],
        ),
      );
      final tiles = find.byType(AnswerTile);
      expect(
        tester.getSize(tiles.at(2)).width,
        tester.getSize(tiles.at(0)).width,
      );
    });
  });
}
