import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/prototype/mock_data.dart';
import 'package:yeman_zefen/prototype/models.dart';
import 'package:yeman_zefen/prototype/prototype_app.dart';
import 'package:yeman_zefen/prototype/prototype_model.dart';

import 'screen_kit.dart';

/// The prototype as a player uses it: tapping through the screens on mock data.
void main() {
  setUpAll(loadAppFonts);

  Future<void> start(WidgetTester tester, PrototypeModel model) async {
    tester.view.physicalSize = phoneSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PrototypeApp(model: model));
    await tester.pump();
  }

  /// Takes the app down and stops the mock downloads, so no timer outlives the test.
  Future<void> finish(WidgetTester tester, PrototypeModel model) async {
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump();
  }

  testWidgets(
    'a mode row opens Mode select with that mode chosen, then era setup',
    (tester) async {
      final model = PrototypeModel(resumeDownloads: false);
      await start(tester, model);

      await tester.tap(find.text('Guess from the Middle'));
      await tester.pumpAndSettle();
      expect(find.text('How do you want to play?'), findsOneWidget);
      expect(model.quickPlay.mode, GameMode.middle);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Pick an era'), findsOneWidget);
      expect(find.text('Start · 10 rounds'), findsOneWidget);
      await finish(tester, model);
    },
  );

  testWidgets('Which Era? hides the song-or-artist choice', (tester) async {
    final model = PrototypeModel(resumeDownloads: false);
    await start(tester, model);

    await tester.tap(find.text('Which Era?'));
    await tester.pumpAndSettle();
    expect(find.text('Guess the'), findsNothing);

    await tester.tap(find.text('Guess the Intro'));
    await tester.pump();
    expect(find.text('Guess the'), findsOneWidget);
    await finish(tester, model);
  });

  testWidgets('the language switch changes every screen live', (tester) async {
    final model = PrototypeModel(resumeDownloads: false);
    await start(tester, model);
    expect(find.text('Ready for a song?'), findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.text('አማርኛ'));
    await tester.pumpAndSettle();
    expect(model.languageCode, 'am');
    expect(find.text('ቅንብሮች'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('መነሻ'));
    await tester.pumpAndSettle();
    expect(find.text('ለዘፈን ዝግጁ ነዎት?'), findsOneWidget);
    await finish(tester, model);
  });

  testWidgets(
    'Home has no pack or download prompt, even offline with nothing downloaded',
    (tester) async {
      final model = PrototypeModel(
        resumeDownloads: false,
        connection: Connection.offline,
        packs: [
          for (final p in mockPacks)
            p.copyWith(status: PackStatus.notInstalled),
        ],
      );
      await start(tester, model);

      expect(find.textContaining('built-in songs'), findsOneWidget);
      expect(find.textContaining('Download'), findsNothing);
      expect(find.text('Needs internet'), findsOneWidget);
      await finish(tester, model);
    },
  );

  testWidgets('offline, eras without enough songs on the phone are disabled', (
    tester,
  ) async {
    final model = PrototypeModel(
      resumeDownloads: false,
      connection: Connection.offline,
    );
    await start(tester, model);

    // The built-in songs have five per era. The '80s and 2000s packs are on the phone.
    expect(model.disabledEras, {EraId.golden, EraId.nineties, EraId.modern});
    await tester.tap(find.text('Guess the Intro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Needs internet or a downloaded pack'), findsNWidgets(3));

    // A disabled era cannot be chosen.
    await tester.tap(find.text('Golden Age'));
    await tester.pump();
    expect(model.quickPlay.generationId, EraId.eighties);
    await finish(tester, model);
  });

  testWidgets('a combination with too few songs switches Start off', (
    tester,
  ) async {
    final model = PrototypeModel(resumeDownloads: false);
    model.quickPlay = const PlaySettings(
      generationId: EraId.golden,
      genre: Genre.hiphop,
    );
    await start(tester, model);
    await tester.tap(find.text('Guess the Intro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not enough songs'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Start'))),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    await finish(tester, model);
  });

  group('Settings › Offline play', () {
    Future<void> openOffline(WidgetTester tester) async {
      await openSettings(tester);
      await tester.tap(find.textContaining('Offline play ·'));
      await tester.pumpAndSettle();
      expect(find.text('Offline play'), findsOneWidget);
    }

    testWidgets('the Settings row shows the packs and an update badge', (
      tester,
    ) async {
      final model = PrototypeModel(resumeDownloads: false);
      await start(tester, model);
      await openSettings(tester);
      // The '80s (12 MB) is installed, the 2000s (15 MB) is installed with an update waiting.
      expect(find.text('Offline play · 2 packs · 27 MB'), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('Download on mobile data asks first when Wi-Fi only is on', (
      tester,
    ) async {
      final model = PrototypeModel(
        resumeDownloads: false,
        connection: Connection.mobile,
      );
      await start(tester, model);
      await openOffline(tester);

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.text('Download on mobile data?'), findsOneWidget);
      expect(find.text('This pack is 14 MB.'), findsOneWidget);

      await tester.tap(find.text('Wait for Wi-Fi'));
      await tester.pumpAndSettle();
      expect(
        model.packs.firstWhere((p) => p.id == 'p-90s').status,
        PackStatus.notInstalled,
      );

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download now'));
      await tester.pump();
      expect(
        model.packs.firstWhere((p) => p.id == 'p-90s').status,
        PackStatus.downloading,
      );
      await finish(tester, model);
    });

    testWidgets('on Wi-Fi, Download starts at once and runs to Downloaded', (
      tester,
    ) async {
      final model = PrototypeModel(
        resumeDownloads: false,
        connection: Connection.wifi,
      );
      await start(tester, model);
      await openOffline(tester);

      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(find.text('Download on mobile data?'), findsNothing);

      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 2));
      expect(
        model.packs.firstWhere((p) => p.id == 'p-90s').status,
        PackStatus.installed,
      );
      await finish(tester, model);
    });

    testWidgets(
      'a failing download shows its error card, and Try again restarts it',
      (tester) async {
        final model = PrototypeModel(resumeDownloads: false)
          ..failNextDownload = PackProblem.downloadFailed;
        await start(tester, model);
        await openOffline(tester);

        await tester.tap(find.text('Download'));
        await tester.pump(const Duration(seconds: 3));
        expect(
          find.text('Download failed. Check your connection and try again.'),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('Try again'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Try again'));
        await tester.pump();
        expect(
          model.packs.firstWhere((p) => p.id == 'p-90s').status,
          PackStatus.downloading,
        );
        await finish(tester, model);
      },
    );

    testWidgets('removing a pack asks first, and Cancel keeps it', (
      tester,
    ) async {
      final model = PrototypeModel(resumeDownloads: false);
      await start(tester, model);
      await openOffline(tester);

      await tester.longPress(find.text("The '80s"));
      await tester.pumpAndSettle();
      expect(
        find.text("Remove The '80s? You can download it again later."),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(
        model.packs.firstWhere((p) => p.id == 'p-80s').status,
        PackStatus.installed,
      );

      await tester.longPress(find.text("The '80s"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(
        model.packs.firstWhere((p) => p.id == 'p-80s').status,
        PackStatus.notInstalled,
      );
      await finish(tester, model);
    });

    testWidgets('offline, Download is switched off and the page says why', (
      tester,
    ) async {
      final model = PrototypeModel(
        resumeDownloads: false,
        connection: Connection.offline,
      );
      await start(tester, model);
      await openOffline(tester);

      expect(
        find.text('Connect to the internet to download packs.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(
        model.packs.firstWhere((p) => p.id == 'p-90s').status,
        PackStatus.notInstalled,
      );
      await finish(tester, model);
    });

    testWidgets('the data toggles flip, and Clear cache empties the cache', (
      tester,
    ) async {
      final model = PrototypeModel(resumeDownloads: false);
      await start(tester, model);
      await openOffline(tester);

      expect(model.wifiOnly, isTrue);
      await tester.tap(find.text('Download packs on Wi-Fi only'));
      await tester.pump();
      expect(model.wifiOnly, isFalse);

      await tester.tap(find.text('Download upcoming songs on mobile data'));
      await tester.pump();
      expect(model.mobilePrefetch, isFalse);

      expect(find.text('Cache 31 MB'), findsOneWidget);
      await tester.tap(find.text('Clear cache'));
      await tester.pump();
      expect(find.text('Cache 0 MB'), findsOneWidget);
      await finish(tester, model);
    });
  });

  group('playing from the prototype', () {
    testWidgets('Play on Home starts a game with what Play shows', (
      tester,
    ) async {
      final model = PrototypeModel(resumeDownloads: false);
      await start(tester, model);

      await tester.tap(find.bySemanticsLabel('Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('1 / 10'), findsOneWidget);
      // The '80s · Intro · Easy is what Play was showing.
      expect(find.text("The '80s"), findsOneWidget);
      expect(find.text('Easy · 10 s'), findsOneWidget);
      expect(find.text('Which song is this?'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Leave game'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Leave'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ready for a song?'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('Start on era setup plays the era and mode that were chosen', (
      tester,
    ) async {
      final model = PrototypeModel(resumeDownloads: false);
      await start(tester, model);
      await tester.tap(find.text('Which Era?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start · 10 rounds'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Which era is this song from?'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('the Leaderboard row on Home opens the board', (tester) async {
      final model = PrototypeModel(resumeDownloads: false);
      await start(tester, model);
      await tester.tap(find.text('Sign in to get a rank'));
      await tester.pumpAndSettle();
      expect(find.text('Want your name up here?'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Ready for a song?'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('Sign in on Settings opens the sheet and signs in', (
      tester,
    ) async {
      final model = PrototypeModel(resumeDownloads: false);
      await start(tester, model);
      await openSettings(tester);
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Keep your scores'), findsOneWidget);

      await tester.tap(find.text('Continue with Google'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Meron');
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();
      expect(model.user.displayName, 'Meron');
      expect(find.text('Meron'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('the whole game reads in Amharic', (tester) async {
      final model = PrototypeModel(resumeDownloads: false, languageCode: 'am');
      await start(tester, model);
      await tester.tap(find.bySemanticsLabel('ይጫወቱ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('ይህ የትኛው ዘፈን ነው?'), findsOneWidget);
      expect(find.text('ፍንጭ'), findsOneWidget);
      expect(find.text('1 / 10'), findsOneWidget);
      await finish(tester, model);
    });
  });

  group('review fixes', () {
    PackItem pack(PrototypeModel m, String id) =>
        m.packs.firstWhere((p) => p.id == id);

    testWidgets(
      'an update keeps the pack on the phone, and Cancel returns it to waiting',
      (tester) async {
        final model = PrototypeModel(resumeDownloads: false);
        await start(tester, model);
        await openSettings(tester);
        await tester.tap(find.textContaining('Offline play ·'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Update · 3 MB'));
        await tester.pump();
        final updating = pack(model, 'p-2000s');
        expect(updating.status, PackStatus.downloading);
        expect(updating.isOnPhone, isTrue);
        expect(model.installedPackCount, 2);
        // The row shows the size of the update, not the whole pack.
        expect(find.text('0% · 50 songs · 3 MB'), findsOneWidget);

        model.cancel('p-2000s');
        await tester.pump();
        expect(pack(model, 'p-2000s').status, PackStatus.updateAvailable);
        await finish(tester, model);
      },
    );

    testWidgets(
      'a finished update leaves the pack installed with no update waiting',
      (tester) async {
        final model = PrototypeModel(resumeDownloads: false);
        await start(tester, model);
        model.download('p-2000s');
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(seconds: 2));
        final done = pack(model, 'p-2000s');
        expect(done.status, PackStatus.installed);
        expect(done.updating, isFalse);
        expect(model.updateAvailable, isFalse);
        await finish(tester, model);
      },
    );

    testWidgets('a failed update keeps the installed pack', (tester) async {
      final model = PrototypeModel(resumeDownloads: false)
        ..failNextDownload = PackProblem.downloadFailed;
      await start(tester, model);
      model.download('p-2000s');
      await tester.pump(const Duration(seconds: 3));
      expect(pack(model, 'p-2000s').status, PackStatus.failed);
      expect(pack(model, 'p-2000s').isOnPhone, isTrue);
      await finish(tester, model);
    });

    testWidgets('Try again is off when offline and asks first on mobile data', (
      tester,
    ) async {
      final model = PrototypeModel(
        resumeDownloads: false,
        connection: Connection.mobile,
      )..failNextDownload = PackProblem.downloadFailed;
      await start(tester, model);
      model.download('p-90s');
      await tester.pump(const Duration(seconds: 3));
      await openSettings(tester);
      await tester.tap(find.textContaining('Offline play ·'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Download on mobile data?'), findsOneWidget);
      await tester.tap(find.text('Wait for Wi-Fi'));
      await tester.pumpAndSettle();
      expect(pack(model, 'p-90s').status, PackStatus.failed);

      model.update(() => model.connection = Connection.offline);
      await tester.pump();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(pack(model, 'p-90s').status, PackStatus.failed);
      await finish(tester, model);
    });

    testWidgets('a corrupt download is fetched again by itself', (
      tester,
    ) async {
      final model = PrototypeModel(resumeDownloads: false)
        ..failNextDownload = PackProblem.corrupt;
      await start(tester, model);
      model.download('p-90s');
      await tester.pump(const Duration(seconds: 3));
      expect(pack(model, 'p-90s').problem, PackProblem.corrupt);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 250));
      expect(pack(model, 'p-90s').status, PackStatus.downloading);
      expect(pack(model, 'p-90s').problem, isNull);
      await finish(tester, model);
    });

    testWidgets('the mock download under way keeps moving', (tester) async {
      final model = PrototypeModel();
      await start(tester, model);
      final before = pack(model, 'p-golden').progress!;
      await tester.pump(const Duration(seconds: 1));
      expect(pack(model, 'p-golden').progress!, greaterThan(before));
      await finish(tester, model);
    });

    testWidgets('Start is off when the chosen era went unavailable offline', (
      tester,
    ) async {
      final model = PrototypeModel(resumeDownloads: false);
      model.quickPlay = const PlaySettings(generationId: EraId.golden);
      await start(tester, model);
      await tester.tap(find.text('Guess the Intro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      model.update(() => model.connection = Connection.offline);
      await tester.pump();

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Start'))),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
      await finish(tester, model);
    });
  });

  testWidgets('sign out and delete account both ask first', (tester) async {
    final model = PrototypeModel(resumeDownloads: false, user: mockSignedIn);
    await start(tester, model);
    await openSettings(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sign out? Your scores stay saved to your account.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(model.user.isGuest, isFalse);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('permanently deletes'), findsOneWidget);
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(model.user.isGuest, isTrue);
    await finish(tester, model);
  });

  testWidgets('the toggles are announced as switches', (tester) async {
    final model = PrototypeModel(resumeDownloads: false);
    await start(tester, model);
    await openSettings(tester);

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sound effects')),
      isSemantics(hasToggledState: true, isToggled: true),
    );
    handle.dispose();
    await finish(tester, model);
  });
}
