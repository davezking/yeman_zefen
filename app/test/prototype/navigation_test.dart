import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/prototype/mock_data.dart';
import 'package:yeman_zefen/prototype/models.dart';
import 'package:yeman_zefen/prototype/prototype_app.dart';
import 'package:yeman_zefen/prototype/prototype_jumps.dart';
import 'package:yeman_zefen/prototype/prototype_model.dart';
import 'package:yeman_zefen/prototype/prototype_router.dart';
import 'package:yeman_zefen/prototype/round_simulation.dart';
import 'package:yeman_zefen/prototype/screens/home_screen.dart';

import 'screen_kit.dart';

/// The sign-off prototype: every flow tapped through on mock data, and the
/// hidden dev menu jumping to every screen.
void main() {
  setUpAll(loadAppFonts);

  PrototypeModel newModel({UserInfo user = mockGuest}) =>
      PrototypeModel(user: user, resumeDownloads: false)
        ..consentRequired = false;

  Future<void> start(
    WidgetTester tester,
    PrototypeModel model, {
    String? path,
    RoundSimulation? sim,
    bool showAppStart = false,
  }) async {
    setUpPhone(tester);
    await tester.pumpWidget(
      PrototypeApp(
        model: model,
        initialLocation: path,
        simulation: sim,
        showAppStart: showAppStart,
      ),
    );
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester, PrototypeModel model) async {
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Navigator).first)).state.uri.path;

  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  /// Opens the dev menu with three fingers on the screen at once.
  Future<void> openMenu(WidgetTester tester) async {
    final fingers = [
      await tester.startGesture(const Offset(100, 400), pointer: 1),
      await tester.startGesture(const Offset(180, 400), pointer: 2),
      await tester.startGesture(const Offset(260, 400), pointer: 3),
    ];
    for (final f in fingers) {
      await f.up();
    }
    await settle(tester);
  }

  testWidgets('first launch → game → results → register', (tester) async {
    final model = newModel(user: mockNewGuest)..firstLaunch = true;
    final sim = RoundSimulation(
      settings: const PlaySettings(),
      totalRounds: 1,
      interstitialEvery: 0,
      random: Random(3),
    );
    await start(tester, model, sim: sim);

    // Language, then the welcome, then straight into round 1.
    expect(location(tester), ProtoPath.language);
    expect(find.textContaining('Choose your language'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(location(tester), ProtoPath.welcome);
    await tester.tap(find.text('Start playing'));
    await settle(tester);
    expect(location(tester), ProtoPath.round);
    expect(model.firstLaunch, isFalse);
    expect(find.text('1 / 10'), findsNothing); // a one-round game
    await tester.pump(const Duration(seconds: 2));
    sim.answer(sim.view.correctIndex);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));

    // Results, then the register sheet from the guest row.
    expect(location(tester), ProtoPath.results);
    expect(find.text('Game complete'), findsOneWidget);
    await tester.tap(find.text('Sign in to put this score on the leaderboard'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('Keep your scores'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pump(const Duration(seconds: 2));
    await tester.enterText(find.byType(TextField), 'Dawit');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(model.user.isGuest, isFalse);
    expect(model.user.displayName, 'Dawit');

    // Home from Results ends the trip (once the "signed in" notice is gone).
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Home'));
    await settle(tester);
    expect(location(tester), ProtoPath.home);
    expect(find.byType(HomeScreen), findsOneWidget);
    await finish(tester, model);
  });

  testWidgets('after the first launch, system back on Results goes to Home', (
    tester,
  ) async {
    final model = newModel(user: mockNewGuest)..firstLaunch = true;
    final sim = RoundSimulation(
      settings: const PlaySettings(),
      totalRounds: 1,
      interstitialEvery: 0,
      random: Random(3),
    );
    await start(tester, model, sim: sim);
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Start playing'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    sim.answer(sim.view.correctIndex);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(location(tester), ProtoPath.results);

    // Not out of the app: Home is beneath.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle(tester);
    expect(location(tester), ProtoPath.home);
    await tester.pump(const Duration(seconds: 2));
    await finish(tester, model);
  });

  testWidgets('Change era or mode leaves Home beneath Mode select', (
    tester,
  ) async {
    final model = newModel();
    await start(tester, model, path: ProtoPath.results);
    await tester.ensureVisible(find.text('Change era or mode'));
    await tester.pump();
    await tester.tap(find.text('Change era or mode'));
    await settle(tester);
    expect(location(tester), ProtoPath.mode);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle(tester);
    expect(location(tester), ProtoPath.home);
    await tester.pump(const Duration(seconds: 2));
    await finish(tester, model);
  });

  testWidgets('a jump keeps an answered consent and drops old Results', (
    tester,
  ) async {
    final model = newModel()
      ..consentDone = true
      ..lastResults = mockResults(sync: ScoreSync.rejected);
    model.resetStates();
    expect(model.consentDone, isTrue);
    expect(model.lastResults, isNull);
    model.dispose();
  });

  testWidgets('app start shows for a moment, then Home', (tester) async {
    final model = newModel();
    await start(tester, model, showAppStart: true);
    expect(location(tester), ProtoPath.splash);
    expect(find.text('Tuning up…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await settle(tester);
    expect(location(tester), ProtoPath.home);
    await finish(tester, model);
  });

  testWidgets('Home → Settings → Offline play → download a pack', (
    tester,
  ) async {
    final model = newModel();
    await start(tester, model);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await settle(tester);
    expect(location(tester), ProtoPath.settings);
    await tester.tap(find.textContaining('Offline play'));
    await settle(tester);
    expect(location(tester), ProtoPath.offlinePlay);

    // The '90s pack is not installed: Download starts it, and it finishes.
    expect(model.packs.firstWhere((p) => p.id == 'p-90s').isOnPhone, isFalse);
    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(
      model.packs.firstWhere((p) => p.id == 'p-90s').status,
      PackStatus.downloading,
    );
    await tester.pump(const Duration(seconds: 6));
    expect(
      model.packs.firstWhere((p) => p.id == 'p-90s').status,
      PackStatus.installed,
    );

    // Back twice: Settings, then Home.
    await tester.tap(find.bySemanticsLabel('Back'));
    await settle(tester);
    expect(location(tester), ProtoPath.settings);
    await tester.tap(find.bySemanticsLabel('Home'));
    await settle(tester);
    expect(location(tester), ProtoPath.home);
    await finish(tester, model);
  });

  testWidgets('Home → Leaderboard → back', (tester) async {
    final model = newModel();
    await start(tester, model);
    await tester.tap(find.text('Leaderboard'));
    await settle(tester);
    expect(location(tester), ProtoPath.leaderboard);
    await tester.tap(find.bySemanticsLabel('Back'));
    await settle(tester);
    expect(location(tester), ProtoPath.home);
    await finish(tester, model);
  });

  testWidgets('Settings toggles change the model', (tester) async {
    final model = newModel();
    await start(tester, model);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await settle(tester);
    expect(model.soundOn, isTrue);
    await tester.tap(find.byType(AppSwitch).first);
    await tester.pump();
    expect(model.soundOn, isFalse);
    await tester.tap(find.text('አማርኛ'));
    await settle(tester);
    expect(model.languageCode, 'am');
    await finish(tester, model);
  });

  testWidgets('account deletion: Settings → Delete → a guest again', (
    tester,
  ) async {
    final model = newModel(user: mockSignedIn);
    await start(tester, model, path: ProtoPath.settings);
    await tester.scrollUntilVisible(
      find.text('Delete account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete account'));
    await settle(tester);
    // The confirmation says what is lost, and Cancel changes nothing.
    expect(
      find.text(
        "This permanently deletes your account and your leaderboard scores. It can't be undone.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete my account'));
    await settle(tester);
    expect(model.user.isGuest, isTrue);
    expect(model.user.bestScore, isNull);
    expect(find.text('Delete account'), findsNothing);
    await finish(tester, model);
  });

  testWidgets('the forced update replaces whatever is open', (tester) async {
    final model = newModel();
    await start(tester, model, path: ProtoPath.leaderboard);
    model.update(() => model.updateRequired = true);
    await settle(tester);
    expect(location(tester), ProtoPath.update);
    await tester.tap(find.text('Play offline songs'));
    await settle(tester);
    expect(location(tester), ProtoPath.home);
    expect(model.offline, isTrue);
    // The network is back: the update is required again.
    model.setConnection(Connection.wifi);
    await settle(tester);
    expect(location(tester), ProtoPath.update);
    await finish(tester, model);
  });

  group('the hidden dev menu', () {
    testWidgets('three fingers open it; Ctrl+Shift+D too', (tester) async {
      final model = newModel();
      await start(tester, model);
      expect(find.text('Prototype dev menu'), findsNothing);
      await openMenu(tester);
      expect(find.text('Prototype dev menu'), findsOneWidget);
      await tester.tapAt(const Offset(180, 20)); // the scrim closes it
      await settle(tester);
      expect(find.text('Prototype dev menu'), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(find.text('Prototype dev menu'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('one or two fingers do not open it', (tester) async {
      final model = newModel();
      await start(tester, model);
      final a = await tester.startGesture(const Offset(100, 400), pointer: 1);
      final b = await tester.startGesture(const Offset(200, 400), pointer: 2);
      await a.up();
      await b.up();
      await settle(tester);
      expect(find.text('Prototype dev menu'), findsNothing);
      await finish(tester, model);
    });

    testWidgets('switches guest / registered, online / offline, en / am', (
      tester,
    ) async {
      final model = newModel();
      await start(tester, model);
      await openMenu(tester);

      await tester.tap(find.text('Registered'));
      await tester.pump();
      expect(model.user.isGuest, isFalse);
      await tester.tap(find.text('Guest, first run'));
      await tester.pump();
      expect(model.user.isGuest, isTrue);
      expect(model.user.bestScore, isNull);

      await tester.tap(find.text('Offline').first);
      await tester.pump();
      expect(model.offline, isTrue);
      await tester.tap(find.text('Wi-Fi'));
      await tester.pump();
      expect(model.offline, isFalse);

      await tester.tap(find.text('አማርኛ'));
      await settle(tester);
      expect(model.languageCode, 'am');
      await tester.tap(find.text('English'));
      await settle(tester);
      expect(model.languageCode, 'en');
      await finish(tester, model);
    });

    for (final lang in ['en', 'am']) {
      testWidgets('jumps to every screen and state, $lang', (tester) async {
        for (final target in prototypeJumps) {
          final model = newModel()..languageCode = lang;
          await start(tester, model);
          await openMenu(tester);
          final chip = find.widgetWithText(ActionChip, target.label);
          await tester.scrollUntilVisible(
            chip,
            150,
            scrollable: find
                .descendant(
                  of: find.byType(DraggableScrollableSheet),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.ensureVisible(chip);
          await tester.pump();
          await tester.tap(chip);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            tester.takeException(),
            isNull,
            reason: 'jumping to ${target.label}',
          );
          // The path is the one asked for, or where it redirects to.
          final here = location(tester);
          expect(
            here == target.path ||
                (target.path == ProtoPath.home && here == ProtoPath.language),
            isTrue,
            reason: '${target.label} opened $here, not ${target.path}',
          );
          await tester.pumpWidget(const SizedBox());
          model.dispose();
          // Timers (the dev menu's delayed sheet) run out.
          await tester.pump(const Duration(seconds: 3));
        }
      });
    }
  });
}
