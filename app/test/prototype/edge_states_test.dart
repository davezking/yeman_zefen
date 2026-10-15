import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/prototype/mock_data.dart';
import 'package:yeman_zefen/prototype/models.dart';
import 'package:yeman_zefen/prototype/prototype_app.dart';
import 'package:yeman_zefen/prototype/prototype_model.dart';
import 'package:yeman_zefen/prototype/screens/message_screens.dart';

import 'screen_kit.dart';

/// The edge states as a player meets them in the prototype: first launch,
/// consent, the forced update, offline, out of songs, a late clip, loading
/// and errors.
void main() {
  setUpAll(loadAppFonts);

  Future<void> start(
    WidgetTester tester,
    PrototypeModel model, {
    bool showAppStart = false,
  }) async {
    tester.view.physicalSize = phoneSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PrototypeApp(model: model, showAppStart: showAppStart),
    );
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester, PrototypeModel model) async {
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  }

  /// Lets a route or a fade finish without waiting for the cassette to stop.
  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  PrototypeModel model0() => PrototypeModel(resumeDownloads: false);

  testWidgets('app start shows the wordmark and "Tuning up…", then Home', (
    tester,
  ) async {
    final model = model0();
    await start(tester, model, showAppStart: true);
    expect(find.text('Tuning up…'), findsOneWidget);
    expect(find.byType(LogoTiles), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Ready for a song?'), findsOneWidget);
    await finish(tester, model);
  });

  group('first launch', () {
    testWidgets('language, then welcome, then straight into a game', (
      tester,
    ) async {
      final model = model0()..firstLaunch = true;
      await start(tester, model);

      // The prompt reads in both scripts before anything is chosen.
      expect(find.text('ቋንቋ ይምረጡ · Choose your language'), findsOneWidget);
      expect(
        find.text('You can change this anytime in Settings.'),
        findsOneWidget,
      );

      // Tapping a language switches the app at once.
      await tester.tap(find.text('አማርኛ'));
      await tester.pumpAndSettle();
      expect(model.languageCode, 'am');
      expect(find.text('ይህን በማንኛውም ጊዜ በቅንብሮች ውስጥ መቀየር ይችላሉ።'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Name the song from its first notes.'), findsOneWidget);
      expect(find.text('Mahmoud Ahmed'), findsOneWidget);
      // No sign-up, download or consent before the first round.
      expect(find.textContaining('Sign in'), findsNothing);
      expect(find.textContaining('Download'), findsNothing);

      await tester.tap(find.text('Start playing'));
      await settle(tester);
      expect(find.text('1 / 10'), findsOneWidget);
      expect(find.text('All eras'), findsOneWidget);
      expect(find.text('Easy · 10 s'), findsOneWidget);
      expect(find.text('Which song is this?'), findsOneWidget);
      expect(model.firstLaunch, isFalse);
      await finish(tester, model);
    });
  });

  group('ad consent', () {
    testWidgets('comes after the first finished game, then Google\'s form, '
        'then Results', (tester) async {
      final model = model0();
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Play'));
      await settle(tester);
      // Let the ten rounds run out, with the ads between them.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 6));
      }
      await settle(tester, 600);
      expect(find.text('Ads keep this game free'), findsOneWidget);
      expect(
        find.text(
          "Next, you'll choose how ads may use your data. You can change this anytime in Settings.",
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      // The placeholder where Google's UMP form appears.
      expect(find.byType(UmpFormPlaceholder), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(UmpFormPlaceholder),
          matching: find.byType(PrimaryButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Game complete'), findsOneWidget);
      expect(model.consentDone, isTrue);
      await finish(tester, model);
    });

    testWidgets('is not asked where it is not required', (tester) async {
      final model = model0()..consentRequired = false;
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Play'));
      await settle(tester);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 6));
      }
      await settle(tester, 600);
      expect(find.text('Game complete'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('Settings › Ad privacy choices opens the same form', (
      tester,
    ) async {
      final model = model0();
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ad privacy choices'));
      await tester.pumpAndSettle();
      expect(find.byType(UmpFormPlaceholder), findsOneWidget);
      await finish(tester, model);
    });
  });

  group('forced update', () {
    testWidgets('replaces Home, and can play the songs on the phone', (
      tester,
    ) async {
      final model = model0()..updateRequired = true;
      await start(tester, model);
      expect(find.text('Time to update'), findsOneWidget);
      expect(find.text('Update on Google Play'), findsOneWidget);

      await tester.tap(find.text('Play offline songs'));
      await tester.pumpAndSettle();
      expect(find.text('Ready for a song?'), findsOneWidget);
      expect(model.offline, isTrue);
      expect(
        find.textContaining("You're offline. You can still play"),
        findsOneWidget,
      );
      await finish(tester, model);
    });

    testWidgets('on iOS it names the App Store', (tester) async {
      final model = model0()
        ..updateRequired = true
        ..showApple = true;
      await start(tester, model);
      expect(find.text('Update on the App Store'), findsOneWidget);
      await finish(tester, model);
    });
  });

  group('out of songs', () {
    testWidgets('offline with every song heard: browse packs or play again', (
      tester,
    ) async {
      final model = model0()
        ..connection = Connection.offline
        ..allSongsPlayed = true;
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pumpAndSettle();
      expect(find.text("You've played every song here"), findsOneWidget);

      await tester.tap(find.text('Browse packs'));
      await tester.pumpAndSettle();
      expect(find.text('Offline play'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play them again'));
      await settle(tester, 600);
      expect(find.text('1 / 10'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('online there is always something new to stream', (
      tester,
    ) async {
      final model = model0()..allSongsPlayed = true;
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Play'));
      await settle(tester);
      expect(find.text('1 / 10'), findsOneWidget);
      await finish(tester, model);
    });
  });

  group('next song loading', () {
    testWidgets('a late clip: "Getting the next song…", then the round', (
      tester,
    ) async {
      final model = model0()..nextClip = ClipArrival.slow;
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Play'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2 / 10'), findsOneWidget);
      expect(find.text('Getting the next song…'), findsOneWidget);
      expect(
        find.text(
          "If it doesn't load in 10 seconds, we'll skip this round. You won't lose points.",
        ),
        findsOneWidget,
      );
      expect(find.byType(SkeletonBox), findsNWidgets(4));
      expect(find.text('Hint'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Which song is this?'), findsOneWidget);
      expect(find.byType(AnswerTile), findsNWidgets(4));
      await finish(tester, model);
    });

    testWidgets('a clip that never comes: skipped after 10 s, with a notice', (
      tester,
    ) async {
      final model = model0()..nextClip = ClipArrival.never;
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Play'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(
          "We skipped a song that wouldn't load or play. No points lost.",
        ),
        findsOneWidget,
      );
      expect(find.text('3 / 10'), findsOneWidget);
      await finish(tester, model);
    });
  });

  group('loading and errors', () {
    testWidgets('a slow leaderboard says it is loading, with a skeleton after '
        'a moment', (tester) async {
      final model = model0()..slowLists = true;
      await start(tester, model);
      await tester.tap(find.text('Sign in to get a rank'));
      await settle(tester, 100);
      expect(find.text('Loading the leaderboard…'), findsOneWidget);
      expect(find.byType(SkeletonBox), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SkeletonBox), findsWidgets);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Selam T.'), findsOneWidget);
      expect(find.byType(SkeletonBox), findsNothing);
      await finish(tester, model);
    });

    testWidgets(
      'a failed leaderboard shows the error, and Try again loads it',
      (tester) async {
        final model = model0()..boardFails = true;
        await start(tester, model);
        await tester.tap(find.text('Sign in to get a rank'));
        await tester.pumpAndSettle();
        expect(find.text('Something went wrong'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Selam T.'), findsOneWidget);
        await finish(tester, model);
      },
    );

    testWidgets('a slow pack list shows row skeletons, then the packs', (
      tester,
    ) async {
      final model = model0()..slowLists = true;
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Offline play ·'));
      await settle(tester, 400);
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.text("The '90s"), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text("The '90s"), findsOneWidget);
      await finish(tester, model);
    });
  });

  group('offline notices', () {
    testWidgets('a game finished offline waits, and is sent when back online', (
      tester,
    ) async {
      final model = model0()
        ..consentRequired = false
        ..connection = Connection.offline;
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Play'));
      await settle(tester);
      // Stops as soon as Results is up, while the notice is still showing.
      for (var i = 0; i < 1000 && model.gamesFinished == 0; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await settle(tester, 600);
      expect(find.text('1 games waiting to be sent'), findsOneWidget);
      expect(model.pendingGames, 1);

      model.setConnection(Connection.wifi);
      await settle(tester);
      expect(
        find.text('Back online. Your scores have been sent.'),
        findsOneWidget,
      );
      expect(model.pendingGames, 0);
      await finish(tester, model);
    });

    testWidgets('when sending fails it says it will try again', (tester) async {
      final model = model0()
        ..pendingGames = 2
        ..syncFails = true
        ..connection = Connection.offline;
      await start(tester, model);
      model.setConnection(Connection.wifi);
      await settle(tester);
      expect(
        find.text("Couldn't send your scores. We'll try again automatically."),
        findsOneWidget,
      );
      expect(model.pendingGames, 2);
      await finish(tester, model);
    });

    testWidgets('losing the connection during a game is noted', (tester) async {
      final model = model0();
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('Play'));
      await settle(tester);
      model.setConnection(Connection.offline);
      await settle(tester);
      expect(find.text("You're offline."), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('the built-in songs are what Home offers offline', (
      tester,
    ) async {
      final model = model0()
        ..connection = Connection.offline
        ..packs = [
          for (final p in mockPacks)
            p.copyWith(status: PackStatus.notInstalled),
        ];
      await start(tester, model);
      expect(
        find.text("You're offline. You can still play the 25 built-in songs."),
        findsOneWidget,
      );
      await finish(tester, model);
    });
  });
}
