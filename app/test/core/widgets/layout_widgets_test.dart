import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';

import 'widget_kit.dart';

/// The layout components added for the hi-fi screens: the hero page, bottom bar,
/// switch, segmented control, chips and settings rows.
void main() {
  setUpAll(loadAppFonts);

  group('AppSwitch', () {
    testWidgets('flips on tap and is announced as a switch with its label', (
      tester,
    ) async {
      var on = false;
      await pumpComponent(
        tester,
        StatefulBuilder(
          builder: (context, set) => AppSwitch(
            value: on,
            onChanged: (v) => set(() => on = v),
            semanticLabel: 'Sound effects',
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Sound effects')),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      await tester.tap(find.byType(AppSwitch));
      await tester.pump();
      expect(on, isTrue);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Sound effects')),
        isSemantics(hasToggledState: true, isToggled: true),
      );
      handle.dispose();
    });

    testWidgets('has a 48 dp touch target around the small track', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        AppSwitch(value: true, onChanged: (_) {}, semanticLabel: 'x'),
      );
      expect(tester.getSize(find.byType(AppSwitch)).height, 48);
    });

    testWidgets('without onChanged it is switched off', (tester) async {
      await pumpComponent(
        tester,
        const AppSwitch(value: true, onChanged: null, semanticLabel: 'x'),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('x')),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });
  });

  group('SegmentedControl', () {
    testWidgets('selects an item on tap, and marks the chosen one', (
      tester,
    ) async {
      var picked = 'a';
      await pumpComponent(
        tester,
        StatefulBuilder(
          builder: (context, set) => SegmentedControl<String>(
            selected: picked,
            onChanged: (v) => set(() => picked = v),
            options: const [
              SegmentOption(value: 'a', label: 'Song'),
              SegmentOption(value: 'b', label: 'Artist'),
            ],
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Song')),
        isSemantics(isSelected: true, isButton: true),
      );
      await tester.tap(find.text('Artist'));
      await tester.pump();
      expect(picked, 'b');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Artist')),
        isSemantics(isSelected: true, isButton: true),
      );
      handle.dispose();
    });

    testWidgets('items are as tall as the tallest when a label wraps', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        SegmentedControl<int>(
          selected: 0,
          onChanged: (_) {},
          options: const [
            SegmentOption(value: 0, label: 'Easy'),
            SegmentOption(
              value: 1,
              label: 'A much longer label that has to wrap onto lines',
            ),
          ],
        ),
      );
      final first = tester.getSize(find.byType(RaisedSurface).at(0)).height;
      final second = tester.getSize(find.byType(RaisedSurface).at(1)).height;
      expect(first, second);
      expect(second, greaterThan(48));
    });
  });

  testWidgets('AppChoiceChip is a 48 dp target and reports selection', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      Align(
        alignment: Alignment.centerLeft,
        child: AppChoiceChip(label: 'Tizita', selected: true, onTap: () {}),
      ),
    );
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Tizita')),
      isSemantics(isSelected: true, isButton: true),
    );
    expect(
      tester.getSize(find.byType(AppChoiceChip)).height,
      greaterThanOrEqualTo(44),
    );
    handle.dispose();
  });

  group('AppBottomBar', () {
    Widget bar(NavTab current, List<String> taps) => AppBottomBar(
      current: current,
      homeLabel: 'Home',
      playLabel: 'Play',
      settingsLabel: 'Settings',
      onHome: () => taps.add('home'),
      onPlay: () => taps.add('play'),
      onSettings: () => taps.add('settings'),
    );

    testWidgets('marks the current tab and sends each tap', (tester) async {
      final taps = <String>[];
      await pumpComponent(tester, bar(NavTab.settings, taps));
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Settings')),
        isSemantics(isSelected: true, isButton: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Home')),
        isNot(isSemantics(isSelected: true)),
      );
      await tester.tap(find.bySemanticsLabel('Home'));
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.tap(find.bySemanticsLabel('Settings'));
      expect(taps, ['home', 'play', 'settings']);
      handle.dispose();
    });

    testWidgets('the Play button is 140 x 62 and the tabs are 52 square', (
      tester,
    ) async {
      await pumpComponent(tester, bar(NavTab.home, []));
      final play = tester.getSize(find.bySemanticsLabel('Play'));
      expect(play.height, 62);
      expect(play.width, greaterThanOrEqualTo(140));
      expect(tester.getSize(find.bySemanticsLabel('Home')), const Size(52, 52));
    });
  });

  group('HeroScaffold', () {
    Widget page({List<Widget>? body, Widget? footer}) => HeroScaffold(
      hero: const SizedBox(height: 100, child: Text('hero')),
      body: body ?? [const Text('one'), const Text('two')],
      footer: footer,
    );

    testWidgets(
      'the body starts 12 dp under the hero, and the hero is above it',
      (tester) async {
        await pumpComponent(tester, SizedBox(height: 700, child: page()));
        final hero = tester.getRect(
          find
              .ancestor(
                of: find.text('hero'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        // Hero padding is 14 above and 26 below the 100 dp content: 140 dp.
        expect(hero.height, 140);
        // The body text starts below the hero's bottom edge minus the overlap, plus
        // the body's 28 dp top padding.
        final one = tester.getTopLeft(find.text('one'));
        expect(
          one.dy - tester.getTopLeft(find.byType(HeroScaffold)).dy,
          140 - 12 + 28,
        );
      },
    );

    testWidgets('the footer sits at the bottom when the content is short', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        SizedBox(
          height: 700,
          child: page(footer: const SizedBox(height: 40, child: Text('go'))),
        ),
      );
      final scaffold = tester.getRect(find.byType(HeroScaffold));
      final footer = tester.getRect(find.text('go'));
      // 22 dp of body padding below the footer.
      expect(scaffold.bottom - footer.bottom, lessThanOrEqualTo(22 + 40));
      expect(footer.top, greaterThan(scaffold.top + 300));
    });

    testWidgets('long content scrolls instead of overflowing', (tester) async {
      await pumpComponent(
        tester,
        SizedBox(
          height: 400,
          child: page(
            body: [
              for (var i = 0; i < 30; i++)
                SizedBox(height: 60, child: Text('row $i')),
            ],
            footer: const Text('go'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('go'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('go'), findsOneWidget);
    });
  });

  group('SettingsRow', () {
    testWidgets('a toggle row flips from anywhere on the row and speaks once', (
      tester,
    ) async {
      var on = true;
      await pumpComponent(
        tester,
        StatefulBuilder(
          builder: (context, set) => SettingsGroup(
            children: [
              SettingsRow.toggle(
                title: 'Vibration',
                subtitle: 'Buzz on answers',
                value: on,
                onChanged: (v) => set(() => on = v),
              ),
            ],
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      // One node, not the title twice.
      expect(find.bySemanticsLabel('Vibration'), findsOneWidget);
      await tester.tap(find.text('Vibration'));
      await tester.pump();
      expect(on, isFalse);
      handle.dispose();
    });

    testWidgets('a link row is a button named with its second line', (
      tester,
    ) async {
      var opened = 0;
      await pumpComponent(
        tester,
        SettingsGroup(
          children: [
            SettingsRow(
              title: 'Offline play',
              subtitle: 'Update available',
              badge: true,
              onTap: () => opened++,
            ),
          ],
        ),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Offline play, Update available'),
        ),
        isSemantics(isButton: true),
      );
      await tester.tap(find.text('Offline play'));
      expect(opened, 1);
      handle.dispose();
    });
  });

  testWidgets('ModeCard reads as one button and shows its tag', (tester) async {
    await pumpComponent(
      tester,
      ModeCard(
        title: 'Guess from the Middle',
        description: 'Harder',
        tag: '+25%',
        icon: Icons.show_chart_rounded,
        iconColor: Colors.red,
        selected: false,
        onTap: () {},
      ),
    );
    final handle = tester.ensureSemantics();
    expect(find.text('+25%'), findsOneWidget);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Guess from the Middle, +25%, Harder'),
      ),
      isSemantics(isButton: true),
    );
    handle.dispose();
  });

  testWidgets('DarkBanner is a live region', (tester) async {
    await pumpComponent(
      tester,
      const DarkBanner(icon: Icons.wifi_off_rounded, text: "You're offline."),
    );
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel("You're offline.")),
      isSemantics(isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('LogoTiles reads as the app name and draws six tiles', (
    tester,
  ) async {
    await pumpComponent(tester, const LogoTiles(semanticLabel: 'Yeman Zefen'));
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Yeman Zefen'), findsOneWidget);
    expect(find.byType(RaisedSurface), findsNWidgets(6));
    handle.dispose();
  });
}
