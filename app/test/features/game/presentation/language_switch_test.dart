import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/l10n/locale_provider.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';

import 'screen_kit.dart';

void main() {
  group('the language choice in Settings', () {
    testWidgets('follows an Amharic device', (tester) async {
      await pumpScreens(tester, location: '/settings', device: const Locale('am', 'ET'));
      expect(find.text(lookupAppLocalizations(amharic).settingsTitle), findsOneWidget);
    });

    testWidgets('switches the screen it is on, at once', (tester) async {
      final h = await pumpScreens(tester, location: '/settings');
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('አማርኛ'));
      await tester.pump();

      expect(find.text(lookupAppLocalizations(amharic).settingsTitle), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      expect(h.container.read(localeProvider), amharic);

      await tester.tap(find.text('English'));
      await tester.pump();
      expect(find.text('Settings'), findsOneWidget);
      expect(h.container.read(localeProvider), english);
    });

    testWidgets('keeps the language while moving between screens', (tester) async {
      final h = await pumpScreens(tester, location: '/settings');
      await tester.tap(find.text('አማርኛ'));
      await tester.pump();

      h.router.go('/setup');
      await tester.pumpAndSettle();
      expect(find.text('ይጀምሩ · 10 ዙሮች'), findsOneWidget);
      expect(find.text('Start · 10 rounds'), findsNothing);
    });
  });

  group('a screen already open', () {
    testWidgets('the setup screen changes language without losing the picked options', (tester) async {
      final h = await pumpScreens(tester, location: '/setup');
      expect(find.text('Start · 10 rounds'), findsOneWidget);

      await h.container.read(localeChoiceProvider.notifier).choose(amharic);
      await tester.pumpAndSettle();

      expect(find.text('ይጀምሩ · 10 ዙሮች'), findsOneWidget);
      expect(find.text('Start · 10 rounds'), findsNothing);
      await tester.tap(find.text('ይጀምሩ · 10 ዙሮች'));
      await tester.pumpAndSettle();
      expect(h.session.startedWith!.mode, GameMode.intro, reason: 'the saved choices survive the switch');
    });

    testWidgets('a round shows its songs in the new script and the new words', (tester) async {
      final h = await pumpScreens(tester, location: '/play', state: playing(roundView()));
      expect(find.text('Song One'), findsOneWidget);
      expect(find.text('Which song is this?'), findsOneWidget);

      await h.container.read(localeChoiceProvider.notifier).choose(amharic);
      await tester.pump();

      expect(find.text('ዘፈን አንድ'), findsOneWidget, reason: 'Fidel when the catalog has it');
      expect(find.text('Song One'), findsNothing);
      expect(find.text('Song Two'), findsOneWidget, reason: 'Latin stands in for a title with no Fidel');
      expect(find.text('Which song is this?'), findsNothing);
      expect(find.text('3 / 10'), findsOneWidget);
    });

    testWidgets('the results list changes script', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState());
      expect(find.text('Song 1'), findsOneWidget);

      await h.container.read(localeChoiceProvider.notifier).choose(amharic);
      await tester.pump();

      expect(find.text('ዘፈን'), findsOneWidget);
      expect(find.text('Song 1'), findsNothing);
    });

    testWidgets('a round in Amharic still lands in English when switched back', (tester) async {
      final h = await pumpScreens(
        tester,
        location: '/play',
        state: playing(roundView()),
        device: const Locale('am'),
      );
      expect(find.text('ዘፈን አንድ'), findsOneWidget);

      await h.container.read(localeChoiceProvider.notifier).choose(english);
      await tester.pump();
      expect(find.text('Song One'), findsOneWidget);
    });
  });

  testWidgets('a name the catalog does not have is shown as Unknown, in both languages', (tester) async {
    final h = await pumpScreens(
      tester,
      location: '/results',
      state: finishedState(unnamed: true),
    );
    expect(find.text('Unknown'), findsWidgets);

    await h.container.read(localeChoiceProvider.notifier).choose(amharic);
    await tester.pump();
    expect(find.text('ያልታወቀ'), findsWidgets);
  });
}

