import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/theme/tokens.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';

import 'widget_kit.dart';

void main() {
  setUpAll(loadAppFonts);

  group('buttons', () {
    testWidgets(
      'PrimaryButton fires when tapped; disabled does not, and is dimmed',
      (tester) async {
        var taps = 0;
        await pumpComponent(
          tester,
          PrimaryButton(label: 'Start', onPressed: () => taps++),
        );
        await tester.tap(find.text('Start'));
        expect(taps, 1);

        await pumpComponent(
          tester,
          const PrimaryButton(label: 'Start', onPressed: null),
        );
        await tester.tap(find.text('Start'), warnIfMissed: false);
        expect(taps, 1);
        expect(
          tester
              .widget<Opacity>(
                find
                    .ancestor(
                      of: find.text('Start'),
                      matching: find.byType(Opacity),
                    )
                    .first,
              )
              .opacity,
          ColorTokens.answerDimOpacity,
        );
      },
    );

    testWidgets(
      'every button is at least the 48 dp touch target, even the small one',
      (tester) async {
        await pumpComponent(
          tester,
          Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: PrimaryButton(
                  label: 'Download',
                  small: true,
                  expand: false,
                  onPressed: () {},
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: AppIconButton(
                  icon: Icons.close_rounded,
                  semanticLabel: 'Cancel',
                  onPressed: () {},
                ),
              ),
              PrimaryButton(label: 'Start', onPressed: () {}),
              SecondaryButton(label: 'Home', onPressed: () {}),
            ],
          ),
        );
        for (final type in [PrimaryButton, AppIconButton, SecondaryButton]) {
          for (final element in find.byType(type).evaluate()) {
            final size = tester.getSize(find.byWidget(element.widget));
            expect(
              size.height,
              greaterThanOrEqualTo(SpacingTokens.touchTargetMin),
              reason: '$type height',
            );
            expect(
              size.width,
              greaterThanOrEqualTo(SpacingTokens.touchTargetMin),
              reason: '$type width',
            );
          }
        }
      },
    );

    testWidgets(
      'a button is a button to a screen reader, and the icon button is named',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpComponent(
          tester,
          Column(
            children: [
              PrimaryButton(label: 'Start', onPressed: () {}),
              AppIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: 'Back',
                onPressed: () {},
              ),
              const PrimaryButton(label: 'Off', onPressed: null),
            ],
          ),
        );
        expect(
          tester.getSemantics(find.text('Start')),
          matchesSemantics(
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
            label: 'Start',
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
        expect(find.bySemanticsLabel('Back'), findsOneWidget);
        expect(
          tester.getSemantics(find.text('Off')),
          matchesSemantics(isButton: true, hasEnabledState: true, label: 'Off'),
        );
        handle.dispose();
      },
    );

    // The press moves the paint transform (not the layout), so read it from the Transform.
    double dropOf(WidgetTester tester) => tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(PrimaryButton),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation()
        .y;

    testWidgets(
      'pressing moves the surface down by its press edge and lifts it back',
      (tester) async {
        await pumpComponent(
          tester,
          PrimaryButton(label: 'Start', onPressed: () {}),
        );
        expect(dropOf(tester), 0);

        final press = await tester.startGesture(
          tester.getCenter(find.text('Start')),
        );
        await tester.pump();
        await tester.pump(MotionTokens.durationPress);
        expect(dropOf(tester), ElevationTokens.primary.first.offset.dy);

        await press.up();
        await tester.pumpAndSettle();
        expect(dropOf(tester), 0);
      },
    );

    testWidgets('with reduced motion, pressing is instant', (tester) async {
      await pumpComponent(
        tester,
        PrimaryButton(label: 'Start', onPressed: () {}),
        disableAnimations: true,
      );
      final press = await tester.startGesture(
        tester.getCenter(find.text('Start')),
      );
      await tester.pump(); // one frame, not the press duration
      expect(dropOf(tester), ElevationTokens.primary.first.offset.dy);
      await press.up();
    });
  });

  group('TimerBar', () {
    testWidgets('fills in proportion and shows the label', (tester) async {
      await pumpComponent(tester, const TimerBar(fraction: 0.73, label: '7 s'));
      expect(find.text('7 s'), findsOneWidget);
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor,
        0.73,
      );
    });

    testWidgets('clamps to the bar, and hides the pill without a label', (
      tester,
    ) async {
      await pumpComponent(tester, const TimerBar(fraction: 1.7));
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor,
        1.0,
      );
      expect(find.byType(Text), findsNothing);

      await pumpComponent(
        tester,
        const TimerBar(fraction: -0.2, label: 'Paused'),
      );
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor,
        0.0,
      );
      expect(find.text('Paused'), findsOneWidget);
    });

    testWidgets('a screen reader hears the spoken label, not the pill', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(
        tester,
        const TimerBar(
          fraction: 0.7,
          label: '7 s',
          semanticLabel: '7 seconds left',
        ),
      );
      expect(find.bySemanticsLabel('7 seconds left'), findsOneWidget);
      expect(find.bySemanticsLabel('7 s'), findsNothing);
      handle.dispose();
    });
  });

  group('PlayingIndicator', () {
    final reels = find.descendant(
      of: find.byType(PlayingIndicator),
      matching: find.byType(RotationTransition),
    );
    AnimationController spinOf(WidgetTester tester) =>
        tester.widgetList<RotationTransition>(reels).first.turns
            as AnimationController;

    testWidgets('the reels turn while playing and stop when it ends', (
      tester,
    ) async {
      var playing = true;
      late StateSetter set;
      await pumpComponent(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return PlayingIndicator(playing: playing);
          },
        ),
      );
      expect(reels, findsNWidgets(2));
      expect(spinOf(tester).isAnimating, isTrue);

      set(() => playing = false);
      await tester.pump();
      expect(spinOf(tester).isAnimating, isFalse);

      set(() => playing = true);
      await tester.pump();
      expect(spinOf(tester).isAnimating, isTrue);
      // Leave the tree so the repeating animation does not outlive the test.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with reduced motion the reels never turn', (tester) async {
      await pumpComponent(
        tester,
        const PlayingIndicator(playing: true),
        disableAnimations: true,
      );
      expect(spinOf(tester).isAnimating, isFalse);
    });

    testWidgets(
      'is the size of the design and says "playing" only while it plays',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpComponent(
          tester,
          const Center(
            child: PlayingIndicator(
              playing: true,
              semanticLabel: 'Clip playing',
            ),
          ),
          disableAnimations: true,
        );
        expect(
          tester.getSize(find.byType(PlayingIndicator)).width,
          SizeTokens.cassetteWidth + 2 * SizeTokens.cassetteRim,
        );
        expect(find.bySemanticsLabel('Clip playing'), findsOneWidget);

        await pumpComponent(
          tester,
          const PlayingIndicator(playing: false, semanticLabel: 'Clip playing'),
          disableAnimations: true,
        );
        expect(find.bySemanticsLabel('Clip playing'), findsNothing);
        handle.dispose();
      },
    );
  });

  group('era widgets', () {
    testWidgets('EraChip is painted in its era color', (tester) async {
      await pumpComponent(
        tester,
        const Align(
          alignment: Alignment.centerLeft,
          child: EraChip(label: "The '80s", generationId: 2),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(EraChip),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, ColorTokens.era80s);
    });

    testWidgets(
      'EraCard fires when tapped, marks the selected one with a ring, and keeps its size when selected',
      (tester) async {
        var taps = 0;
        Widget card(bool selected) => EraCard(
          label: "The '80s",
          generationId: 2,
          selected: selected,
          onTap: () => taps++,
        );

        await pumpComponent(tester, card(false));
        final unselectedSize = tester.getSize(find.byType(EraCard));
        await tester.tap(find.text("The '80s"));
        expect(taps, 1);

        await pumpComponent(tester, card(true));
        expect(tester.getSize(find.byType(EraCard)), unselectedSize);
        final ring = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(EraCard),
                matching: find.byType(Container),
              ),
            )
            .first;
        expect(
          ((ring.decoration! as BoxDecoration).border! as Border).top.color,
          ColorTokens.eraSelectedRing,
        );
      },
    );

    testWidgets('an unavailable EraCard is faded and inert', (tester) async {
      var taps = 0;
      await pumpComponent(
        tester,
        EraCard(
          label: 'The 2000s',
          generationId: 4,
          selected: false,
          enabled: false,
          onTap: () => taps++,
        ),
      );
      await tester.tap(find.text('The 2000s'), warnIfMissed: false);
      expect(taps, 0);
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byType(EraCard),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        ColorTokens.answerDimOpacity,
      );
    });

    testWidgets('EraCard is read with its years', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(
        tester,
        EraCard(
          label: 'Golden Age',
          subtitle: 'Before 1980',
          generationId: 1,
          selected: false,
          onTap: () {},
        ),
      );
      expect(find.bySemanticsLabel('Golden Age, Before 1980'), findsOneWidget);
      handle.dispose();
    });
  });

  group('PackCard', () {
    Future<void> pump(WidgetTester tester, PackCard card) =>
        pumpComponent(tester, card);

    testWidgets('not installed: shows the action and fires it', (tester) async {
      var taps = 0;
      await pump(
        tester,
        PackCard(
          name: 'Modern',
          meta: '30 songs · 9 MB',
          status: PackStatus.notInstalled,
          actionLabel: 'Download',
          onAction: () => taps++,
        ),
      );
      await tester.tap(find.text('Download'));
      expect(taps, 1);
    });

    testWidgets(
      'downloading: a progress bar at the right place and a named cancel button',
      (tester) async {
        var cancelled = 0;
        final handle = tester.ensureSemantics();
        await pump(
          tester,
          PackCard(
            name: 'Golden Age',
            meta: '42% · 60 songs',
            status: PackStatus.downloading,
            progress: 0.42,
            cancelLabel: 'Cancel',
            onCancel: () => cancelled++,
          ),
        );
        expect(
          tester
              .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
              .widthFactor,
          0.42,
        );
        expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close_rounded));
        expect(cancelled, 1);
        handle.dispose();
      },
    );

    testWidgets('verifying: an unmeasured bar and its status, no button', (
      tester,
    ) async {
      await pump(
        tester,
        const PackCard(
          name: "The '90s",
          meta: '45 songs',
          status: PackStatus.verifying,
          statusLabel: 'Checking files…',
        ),
      );
      expect(find.text('Checking files…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
      await tester.pumpWidget(
        const SizedBox(),
      ); // stop the indeterminate animation
    });

    testWidgets(
      'installed shows a check and "Downloaded"; built-in shows only its word',
      (tester) async {
        await pump(
          tester,
          const PackCard(
            name: "The '80s",
            meta: '40 songs',
            status: PackStatus.installed,
            statusLabel: 'Downloaded',
          ),
        );
        expect(find.text('Downloaded'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);

        await pump(
          tester,
          const PackCard(
            name: 'Built-in songs',
            meta: '25 songs',
            status: PackStatus.builtIn,
            statusLabel: 'Always there',
          ),
        );
        expect(find.text('Always there'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(find.byType(PrimaryButton), findsNothing);
      },
    );

    testWidgets('update available: says so and offers the update', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        PackCard(
          name: 'The 2000s',
          meta: '50 songs',
          status: PackStatus.updateAvailable,
          statusLabel: 'Update available',
          actionLabel: 'Update · 3 MB',
          onAction: () => taps++,
        ),
      );
      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.text('Update · 3 MB'));
      expect(taps, 1);
    });

    testWidgets('failed: an announced error with a retry button', (
      tester,
    ) async {
      var retries = 0;
      await pump(
        tester,
        PackCard(
          name: 'Golden Age',
          meta: '60 songs',
          status: PackStatus.failed,
          errorMessage: 'Download failed.',
          retryLabel: 'Try again',
          onRetry: () => retries++,
        ),
      );
      expect(find.text('Download failed.'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });
  });

  group('ScoreBadge and ListRow', () {
    testWidgets('the best badge has a star; the points badge does not', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        const Column(
          children: [
            ScoreBadge(label: '563 pts'),
            ScoreBadge.best(label: 'New personal best'),
          ],
        ),
      );
      expect(find.text('563 pts'), findsOneWidget);
      expect(find.text('New personal best'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets(
      'ListRow fires, is read as title and subtitle, and is at least 64 dp tall',
      (tester) async {
        var taps = 0;
        final handle = tester.ensureSemantics();
        await pumpComponent(
          tester,
          ListRow(
            title: 'Leaderboard',
            subtitle: 'Sign in to get a rank',
            icon: Icons.emoji_events_outlined,
            dark: true,
            onTap: () => taps++,
          ),
        );
        await tester.tap(find.text('Leaderboard'));
        expect(taps, 1);
        expect(
          find.bySemanticsLabel('Leaderboard, Sign in to get a rank'),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byType(ListRow)).height,
          greaterThanOrEqualTo(SizeTokens.listRowMinHeight),
        );
        handle.dispose();
      },
    );
  });

  group('dialog and bottom sheet', () {
    Widget opener(
      Future<Object?> Function(BuildContext) open,
      void Function(Object?) done,
    ) => Builder(
      builder: (context) => TextButton(
        onPressed: () async => done(await open(context)),
        child: const Text('open'),
      ),
    );

    testWidgets('showAppDialog resolves true on confirm and false on cancel', (
      tester,
    ) async {
      Object? result = 'unset';
      await pumpComponent(
        tester,
        opener(
          (c) => showAppDialog(
            c,
            title: 'Leave this game?',
            body: 'Your score will not be saved.',
            confirmLabel: 'Leave',
            cancelLabel: 'Keep playing',
          ),
          (r) => result = r,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Leave this game?'), findsOneWidget);
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(result, true);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep playing'));
      await tester.pumpAndSettle();
      expect(result, false);
    });

    testWidgets(
      'showAppBottomSheet shows its content under a grabber and returns what it pops',
      (tester) async {
        Object? result = 'unset';
        await pumpComponent(
          tester,
          opener(
            (c) => showAppBottomSheet<String>(
              c,
              semanticLabel: 'Hint',
              builder: (sheet) => PrimaryButton(
                label: 'Watch ad',
                onPressed: () => Navigator.of(sheet).pop('watched'),
              ),
            ),
            (r) => result = r,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(AppSheet), findsOneWidget);
        await tester.tap(find.text('Watch ad'));
        await tester.pumpAndSettle();
        expect(result, 'watched');
      },
    );
  });

  group('text scale', () {
    // Every component must fit a 360 dp phone at 1.0 and 1.3, in English and
    // Amharic. An overflow shows up as a Flutter error, which takeException returns.
    for (final locale in [const Locale('en'), const Locale('am')]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          '${locale.languageCode} at $scale: components fit without overflow',
          (tester) async {
            final am = locale.languageCode == 'am';
            String t(String en, String amharic) => am ? amharic : en;
            await pumpComponent(
              tester,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    label: t('Start · 10 rounds', 'ይጀምሩ · 10 ዙሮች'),
                    onPressed: () {},
                  ),
                  SecondaryButton(
                    label: t('Change era or mode', 'ዘመን ወይም ጨዋታ ይቀይሩ'),
                    onPressed: () {},
                  ),
                  EqualHeightGrid(
                    children: [
                      AnswerTile(
                        text: t('Mahmoud Ahmed', 'ማሕሙድ አሕመድ'),
                        state: AnswerState.correct,
                        stateLabel: t('Correct', 'ትክክል'),
                      ),
                      AnswerTile(
                        text: t('Tilahun Gessesse', 'ጥላሁን ገሠሠ'),
                        state: AnswerState.wrong,
                        stateLabel: t('Your pick', 'የእርስዎ ምርጫ'),
                      ),
                    ],
                  ),
                  TimerBar(fraction: 0.5, label: t('Paused', 'ቆሟል')),
                  Wrap(
                    spacing: 8,
                    children: [
                      EraChip(
                        label: t('Golden Age', 'ወርቃማው ዘመን'),
                        generationId: 1,
                      ),
                      EraChip(
                        label: t('The 2000s', 'የ2000ዎቹ'),
                        generationId: 4,
                      ),
                    ],
                  ),
                  ListRow(
                    title: t('Guess from the Middle', 'ከመሀል ይገምቱ'),
                    subtitle: t('Harder · +25% points', 'ይከብዳል · +25% ነጥብ'),
                    icon: Icons.graphic_eq_rounded,
                    onTap: () {},
                  ),
                  PackCard(
                    name: t('Golden Age', 'ወርቃማው ዘመን'),
                    meta: t('42% · 60 songs · 18 MB', '42% · 60 ዘፈኖች · 18 ሜባ'),
                    status: PackStatus.updateAvailable,
                    statusLabel: t('Update available', 'ማሻሻያ አለ'),
                    actionLabel: t('Update · 3 MB', 'ያዘምኑ · 3 ሜባ'),
                    onAction: () {},
                  ),
                  PackCard(
                    name: t('Golden Age', 'ወርቃማው ዘመን'),
                    meta: t('60 songs · 18 MB', '60 ዘፈኖች · 18 ሜባ'),
                    status: PackStatus.failed,
                    errorMessage: t(
                      'Download failed. Check your connection and try again.',
                      'ማውረዱ አልተሳካም። ግንኙነትዎን አረጋግጠው እንደገና ይሞክሩ።',
                    ),
                    retryLabel: t('Try again', 'እንደገና ይሞክሩ'),
                    onRetry: () {},
                  ),
                  ScoreBadge.best(
                    label: t('New personal best', 'አዲስ የግል ምርጥ ውጤት'),
                  ),
                ],
              ),
              locale: locale,
              textScale: scale,
              disableAnimations: true,
              height: 2400,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
