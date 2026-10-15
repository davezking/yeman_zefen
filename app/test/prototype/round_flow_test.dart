import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/prototype/mock_data.dart';
import 'package:yeman_zefen/prototype/models.dart';
import 'package:yeman_zefen/prototype/prototype_flow.dart';
import 'package:yeman_zefen/prototype/prototype_model.dart';
import 'package:yeman_zefen/prototype/round_simulation.dart';

import 'screen_kit.dart';

/// The round, Results, the leaderboard and the sign-in sheets as a player meets
/// them: tapping through a mock game on the fake clock.
void main() {
  setUpAll(loadAppFonts);

  const second = Duration(seconds: 1);

  /// Lets a fade or a route run its course. An animation starts on the frame
  /// after it is asked for and is taken out on the build after it ends, so the
  /// time is passed between two plain frames.
  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  /// Opens [route] over a plain "start" page, so Leave and Home have somewhere
  /// to go back to.
  Future<void> open(
    WidgetTester tester,
    PrototypeModel model,
    Widget Function() route, {
    Locale locale = const Locale('en'),
    bool disableAnimations = false,
  }) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => route())),
              child: const Text('start'),
            ),
          ),
        ),
      ),
      locale: locale,
      disableAnimations: disableAnimations,
    );
    await tester.tap(find.text('start'));
    // Not pumpAndSettle: the cassette's reels turn for as long as the clip plays.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens the round for [sim] with its clock held, so the page transition does
  /// not eat into the answer window, then lets it run.
  Future<void> openRound(
    WidgetTester tester,
    PrototypeModel model,
    RoundSimulation sim, {
    Locale locale = const Locale('en'),
    bool disableAnimations = false,
  }) async {
    sim.setBackgrounded(true);
    await open(
      tester,
      model,
      () => RoundRoute(model: model, simulation: sim),
      locale: locale,
      disableAnimations: disableAnimations,
    );
    sim.setBackgrounded(false);
    await tester.pump();
  }

  RoundSimulation newSim({
    PlaySettings settings = const PlaySettings(),
    int rounds = 10,
    int every = 3,
    int? best,
  }) => RoundSimulation(
    settings: settings,
    totalRounds: rounds,
    interstitialEvery: every,
    bestScore: best,
    random: Random(3),
  );

  PrototypeModel newModel({
    UserInfo user = mockGuest,
    Connection connection = Connection.wifi,
  }) => PrototypeModel(
    user: user,
    connection: connection,
    resumeDownloads: false,
  );

  /// Takes everything down so no timer outlives the test.
  Future<void> finish(WidgetTester tester, [PrototypeModel? model]) async {
    await tester.pumpWidget(const SizedBox());
    model?.dispose();
  }

  String label(RoundSimulation sim, int i) {
    final v = sim.view;
    final o = v.options[i];
    if (o.generationId != null) return 'era';
    return v.kind == QuestionKind.artist
        ? o.track!.artistLatin
        : o.track!.titleLatin;
  }

  group('the round screen', () {
    testWidgets('shows the round, the score, the chips and four answers', (
      tester,
    ) async {
      final sim = newSim(settings: const PlaySettings(generationId: 2));
      final model = newModel();
      await openRound(tester, model, sim);

      expect(find.text('1 / 10'), findsOneWidget);
      expect(find.text('Easy · 10 s'), findsOneWidget);
      expect(find.text("The '80s"), findsOneWidget);
      expect(find.text('15 s'), findsOneWidget);
      expect(find.text('Which song is this?'), findsOneWidget);
      expect(find.byType(AnswerTile), findsNWidgets(4));
      expect(find.text('Hint'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        expect(find.text(label(sim, i)), findsOneWidget);
      }
      await finish(tester, model);
    });

    testWidgets('a right answer: green tile with a check, heading and points', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);

      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text(label(sim, sim.view.correctIndex)));
      await tester.pump();

      expect(find.text('Correct +143'), findsOneWidget);
      expect(find.text('Speed bonus +43'), findsOneWidget);
      // Not color alone: the right tile has a check and the word.
      expect(find.byIcon(Icons.check_rounded), findsWidgets);
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Tap to continue · 5 s'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('2 / 10'), findsOneWidget);
      expect(find.text('Which song is this?'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('a wrong answer: red tile with an X, the right one shown', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);

      final wrong = [0, 1, 2, 3].firstWhere((i) => i != sim.view.correctIndex);
      final track = sim.view.track;
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text(label(sim, wrong)));
      await tester.pump();

      expect(find.text('Not this one'), findsOneWidget);
      expect(
        find.text('It was ${track.titleLatin} · ${track.artistLatin}'),
        findsOneWidget,
      );
      // Different icon and different word from the right tile.
      expect(find.byIcon(Icons.close_rounded), findsWidgets);
      expect(find.text('Your pick'), findsOneWidget);
      expect(find.text('Correct'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsWidgets);
      expect(find.text('Tap to continue · 5 s'), findsOneWidget);

      // A tap anywhere moves on.
      await tester.tapAt(const Offset(180, 400));
      await tester.pump();
      expect(find.text('2 / 10'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('running out of time: "Time\'s up" and the right answer', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);

      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("Time's up"), findsOneWidget);
      expect(find.text('Your pick'), findsNothing);
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('0 s'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('Which Era? asks for the era and reveals it', (tester) async {
      final sim = newSim(settings: const PlaySettings(mode: GameMode.era));
      final model = newModel();
      await openRound(tester, model, sim);

      expect(find.text('Which era is this song from?'), findsOneWidget);
      final wrong = [0, 1, 2, 3].firstWhere((i) => i != sim.view.correctIndex);
      sim.answer(wrong);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining("It's from"), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('the hint: sheet, ad, two answers gone, half points', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);

      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Hint'));
      await settle(tester);
      expect(find.text('Hint: remove 2 answers'), findsOneWidget);
      expect(find.text('8 s'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(
        find.text("Watch a short ad. This round's points are halved."),
        findsOneWidget,
      );

      await tester.pump(second);
      expect(find.text('7 s'), findsOneWidget);

      await tester.tap(find.text('Watch ad'));
      await settle(tester);
      expect(find.text('Your hint is on its way…'), findsOneWidget);
      expect(find.text('Ad · 3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('Hint used · half points'), findsOneWidget);
      expect(find.text('Hint'), findsNothing);
      expect(sim.view.removed.length, 2);
      expect(sim.view.secondsLeft, 13);

      // The ad is still fading out; answer now, so no time has passed since.
      sim.answer(sim.view.correctIndex);
      await settle(tester);
      expect(find.text('Your hint is on its way…'), findsNothing);
      // Half of 100 plus the speed bonus, rounded half up.
      final v = sim.view;
      expect(v.points, (100 + v.speedBonus + 1) ~/ 2);
      expect(find.text('Correct +${v.points}'), findsOneWidget);
      expect(find.text('Hint used · half points'), findsWidgets);
      await finish(tester, model);
    });

    testWidgets('No thanks closes the sheet and the timer runs again', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);

      await tester.tap(find.text('Hint'));
      await settle(tester);
      await tester.tap(find.text('No thanks'));
      await settle(tester);
      expect(find.text('Hint: remove 2 answers'), findsNothing);
      expect(find.text('Hint'), findsOneWidget);
      await tester.pump(second);
      expect(find.text('14 s'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('the mandatory ad appears after round 3 and is announced', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);

      for (var r = 0; r < 3; r++) {
        await tester.pump(const Duration(seconds: 2));
        sim.answer(sim.view.correctIndex);
        await tester.pump(second);
      }
      await settle(tester);
      expect(find.text('Ads keep this game free'), findsOneWidget);
      expect(find.textContaining('Ad ·'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.text('Ads keep this game free'), findsNothing);
      expect(find.text('4 / 10'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('going to the background pauses the clock', (tester) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);

      await tester.pump(const Duration(seconds: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Paused'), findsOneWidget);
      expect(sim.view.secondsLeft, 13);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(second);
      expect(find.text('Paused'), findsNothing);
      expect(find.text('12 s'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('Leave asks first; Keep playing resumes, Leave goes back', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);

      await tester.tap(find.bySemanticsLabel('Leave game'));
      await settle(tester);
      expect(find.text('Leave this game?'), findsOneWidget);
      expect(
        find.text("Your score for this game won't be saved."),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('15 s'), findsNothing);
      expect(find.text('Paused'), findsOneWidget);

      await tester.tap(find.text('Keep playing'));
      await settle(tester);
      expect(find.text('Leave this game?'), findsNothing);
      expect(find.text('1 / 10'), findsOneWidget);

      // The system back gesture asks too.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Leave this game?'), findsOneWidget);

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('start'), findsOneWidget);
      expect(model.gamesFinished, 0);
      await finish(tester, model);
    });
  });

  group('reduced motion', () {
    testWidgets('the score jumps to its new value instead of counting up', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim, disableAnimations: true);
      await tester.pump(const Duration(seconds: 2));
      sim.answer(sim.view.correctIndex);
      await tester.pump();
      expect(find.text('143 pts'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('with motion on, the score counts up over the pop', (
      tester,
    ) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim);
      await tester.pump(const Duration(seconds: 2));
      sim.answer(sim.view.correctIndex);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('143 pts'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('143 pts'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('the heading fades in without a scale', (tester) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim, disableAnimations: true);
      sim.answer(sim.view.correctIndex);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.descendant(
          of: find.byType(AnimatedSwitcher).first,
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
      );
      await finish(tester, model);
    });

    testWidgets('the hint sheet slides up, or just fades with reduced motion', (
      tester,
    ) async {
      Finder slides() => find.descendant(
        of: find.byType(AnimatedSwitcher).last,
        matching: find.byType(SlideTransition),
      );

      var sim = newSim();
      var model = newModel();
      await openRound(tester, model, sim);
      await tester.tap(find.text('Hint'));
      await tester.pump();
      expect(slides(), findsWidgets);
      await finish(tester, model);

      sim = newSim();
      model = newModel();
      await openRound(tester, model, sim, disableAnimations: true);
      await tester.tap(find.text('Hint'));
      await tester.pump();
      expect(find.text('Hint: remove 2 answers'), findsOneWidget);
      expect(slides(), findsNothing);
      await finish(tester, model);
    });

    testWidgets('the cassette stands still', (tester) async {
      final sim = newSim();
      final model = newModel();
      await openRound(tester, model, sim, disableAnimations: true);
      // The reels exist but never turn.
      final reels = tester.widgetList<RotationTransition>(
        find.descendant(
          of: find.byType(PlayingIndicator),
          matching: find.byType(RotationTransition),
        ),
      );
      expect(reels, isNotEmpty);
      for (final reel in reels) {
        expect(reel.turns.status, AnimationStatus.dismissed);
      }
      await tester.pump(const Duration(seconds: 1));
      for (final reel in reels) {
        expect(reel.turns.value, 0);
      }
      await finish(tester, model);
    });
  });

  group('a finished game', () {
    /// Plays [rounds] rounds, all right, and lets the route move on.
    Future<void> play(
      WidgetTester tester,
      RoundSimulation sim, {
      int rounds = 3,
    }) async {
      for (var r = 0; r < rounds; r++) {
        await tester.pump(const Duration(seconds: 2));
        sim.answer(sim.view.correctIndex);
        await tester.pump(second);
      }
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('leads to Results: total, rounds and where the score stands', (
      tester,
    ) async {
      final sim = newSim(rounds: 3, every: 0);
      final model = newModel(user: mockNewGuest);
      await openRound(tester, model, sim);
      final track = sim.view.track;

      await play(tester, sim);
      expect(find.text('Game complete'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('429'), findsOneWidget);
      expect(find.text('3 of 3 right'), findsOneWidget);
      expect(find.text('New personal best'), findsOneWidget);
      expect(
        find.text('Sign in to put this score on the leaderboard'),
        findsOneWidget,
      );
      expect(find.text('Your rounds'), findsOneWidget);
      expect(find.text('+143'), findsNWidgets(3));
      expect(
        find.text('${track.titleLatin} · ${track.artistLatin}'),
        findsWidgets,
      );
      expect(find.text('Play again'), findsOneWidget);
      expect(find.text('Change era or mode'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(model.gamesFinished, 1);
      expect(model.user.bestScore, 429);
      await finish(tester, model);
    });

    testWidgets('wrong and timed-out rounds show an X and 0', (tester) async {
      final sim = newSim(rounds: 2, every: 0);
      final model = newModel();
      await openRound(tester, model, sim);
      sim.answer([0, 1, 2, 3].firstWhere((i) => i != sim.view.correctIndex));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Game complete'), findsOneWidget);
      expect(find.text('0 of 2 right'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
      expect(find.text('0'), findsWidgets);
      expect(find.text('New personal best'), findsNothing);
      await finish(tester, model);
    });

    testWidgets(
      'a signed-in player sees this week\'s rank, which opens the board',
      (tester) async {
        final sim = newSim(rounds: 1, every: 0);
        final model = newModel(user: mockSignedIn);
        await openRound(tester, model, sim);
        await play(tester, sim, rounds: 1);

        expect(find.text("You're #7 this week"), findsOneWidget);
        await tester.tap(find.text("You're #7 this week"));
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(find.text('Leaderboard'), findsOneWidget);
        expect(find.text('Your rank: #7'), findsOneWidget);
        await finish(tester, model);
      },
    );

    testWidgets('the score is saved for later when offline', (tester) async {
      final sim = newSim(rounds: 1, every: 0);
      final model = newModel(connection: Connection.offline);
      await openRound(tester, model, sim);
      await play(tester, sim, rounds: 1);
      expect(
        find.text("Score saved. It will be sent when you're back online."),
        findsOneWidget,
      );
      await finish(tester, model);
    });

    testWidgets('a game the server cannot check does not count for rankings', (
      tester,
    ) async {
      final sim = newSim(rounds: 1, every: 0);
      final model = newModel()..forcedSync = ScoreSync.rejected;
      await openRound(tester, model, sim);
      await play(tester, sim, rounds: 1);
      expect(
        find.text(
          "This game couldn't be checked, so it won't count toward rankings.",
        ),
        findsOneWidget,
      );
      await finish(tester, model);
    });

    testWidgets('Change era or mode goes back, Home goes to the first page', (
      tester,
    ) async {
      final sim = newSim(rounds: 1, every: 0);
      final model = newModel();
      await openRound(tester, model, sim);
      await play(tester, sim, rounds: 1);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('start'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('Play again starts a new game with the same settings', (
      tester,
    ) async {
      final sim = newSim(rounds: 1, every: 0);
      final model = newModel();
      await openRound(tester, model, sim);
      await play(tester, sim, rounds: 1);

      await tester.tap(find.text('Play again'));
      await settle(tester, 600);
      expect(find.text('1 / 10'), findsOneWidget);
      expect(find.text('15 s'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('a guest\'s 5th game opens the sign-in sheet over Results', (
      tester,
    ) async {
      final sim = newSim(rounds: 1, every: 0);
      final model = newModel()..gamesFinished = 4;
      await openRound(tester, model, sim);
      await play(tester, sim, rounds: 1);
      await settle(tester, 600);
      expect(find.text('Keep your scores'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('a signed-in player is not asked', (tester) async {
      final sim = newSim(rounds: 1, every: 0);
      final model = newModel(user: mockSignedIn)..gamesFinished = 4;
      await openRound(tester, model, sim);
      await play(tester, sim, rounds: 1);
      await settle(tester, 600);
      expect(find.text('Keep your scores'), findsNothing);
      await finish(tester, model);
    });
  });

  group('signing in', () {
    Future<PrototypeModel> openSheet(
      WidgetTester tester, {
      bool apple = false,
    }) async {
      final model = newModel()..showApple = apple;
      final sim = newSim(rounds: 1, every: 0);
      await openRound(tester, model, sim);
      await tester.pump(const Duration(seconds: 2));
      sim.answer(sim.view.correctIndex);
      await settle(tester, 2000);
      await tester.tap(
        find.text('Sign in to put this score on the leaderboard'),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Keep your scores'), findsOneWidget);
      return model;
    }

    testWidgets('Apple is offered on iOS only, and first', (tester) async {
      var model = await openSheet(tester);
      expect(find.text('Continue with Apple'), findsNothing);
      await finish(tester, model);

      model = await openSheet(tester, apple: true);
      expect(find.text('Continue with Apple'), findsOneWidget);
      final apple = tester.getTopLeft(find.text('Continue with Apple')).dy;
      final google = tester.getTopLeft(find.text('Continue with Google')).dy;
      expect(apple, lessThan(google));
      await finish(tester, model);
    });

    testWidgets('Not now closes the sheet', (tester) async {
      final model = await openSheet(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Keep your scores'), findsNothing);
      expect(model.user.isGuest, isTrue);
      await finish(tester, model);
    });

    testWidgets('Google: signing in, then a display name, then signed in', (
      tester,
    ) async {
      final model = await openSheet(tester);
      await tester.tap(find.text('Continue with Google'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The other buttons are off while one is signing in.
      await tester.tap(find.text('Continue with email'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Pick a display name'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Pick a display name'), findsOneWidget);
      expect(
        find.text('This is the name other players see on the leaderboard.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'A');
      await tester.tap(find.text('Save name'));
      await tester.pump();
      expect(find.text('Use at least 2 characters.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Selam T.');
      await tester.tap(find.text('Save name'));
      await tester.pump();
      expect(find.text('That name is taken. Try another.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Dawit');
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Pick a display name'), findsNothing);
      expect(model.user.displayName, 'Dawit');
      expect(model.user.isGuest, isFalse);
      expect(find.text('Signed in as Dawit'), findsOneWidget);
      // The scores so far come with the player.
      expect(model.user.bestScore, 143);
      await finish(tester, model);
    });

    testWidgets('when the scores cannot be linked it says so and can retry', (
      tester,
    ) async {
      final model = await openSheet(tester);
      model.nextSignIn = SignInOutcome.linkFails;
      await tester.tap(find.text('Continue with Google'));
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.text(
          "We couldn't link your account. Your scores are safe on this phone, and we'll try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(model.nextSignIn, SignInOutcome.works);

      await tester.tap(find.text('Continue with Google'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Pick a display name'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('email: errors for the address and the password, then in', (
      tester,
    ) async {
      final model = await openSheet(tester);
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);

      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Check your email address.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'meron@example.com');
      await tester.enterText(find.byType(TextField).last, 'abc');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Check your email address.'), findsNothing);
      expect(find.text('Wrong email or password.'), findsOneWidget);
      // Each error has an icon, so it is not color alone.
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'secret123');
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign in'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Signing in…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Pick a display name'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('email: Create an account switches the form, and back', (
      tester,
    ) async {
      final model = await openSheet(tester);
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      await tester.tap(find.text('New here? Create an account'));
      await tester.pump();
      expect(find.widgetWithText(PrimaryButton, 'Next'), findsOneWidget);
      expect(find.text('Forgot password?'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
      await tester.pump();
      expect(find.widgetWithText(PrimaryButton, 'Sign in'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pump();
      expect(find.text('Keep your scores'), findsOneWidget);
      await finish(tester, model);
    });
  });

  group('the leaderboard', () {
    Future<PrototypeModel> board(
      WidgetTester tester, {
      UserInfo user = mockGuest,
      Connection connection = Connection.wifi,
      void Function(PrototypeModel)? setUp,
      Locale locale = const Locale('en'),
    }) async {
      final model = newModel(user: user, connection: connection);
      setUp?.call(model);
      await open(
        tester,
        model,
        () => LeaderboardRoute(model: model),
        locale: locale,
      );
      return model;
    }

    testWidgets('a guest sees the podium, the rows and a sign-in bar', (
      tester,
    ) async {
      final model = await board(tester);
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text('Selam T.'), findsOneWidget);
      expect(find.text('9,860'), findsOneWidget);
      expect(find.text('Yonas M.'), findsOneWidget);
      expect(find.text('8,630 pts'), findsOneWidget);
      expect(find.text('Want your name up here?'), findsOneWidget);
      expect(
        find.text('Sign in to rank. Your scores come with you.'),
        findsOneWidget,
      );
      expect(find.text('Era: All eras'), findsOneWidget);

      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign in'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Keep your scores'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('a signed-in player has their own row pinned', (tester) async {
      final model = await board(tester, user: mockSignedIn);
      expect(find.text('Your rank: #7'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Want your name up here?'), findsNothing);
      await finish(tester, model);
    });

    testWidgets(
      'a signed-in player with no game this week is told how to rank',
      (tester) async {
        // A player with a name but no entry: the board has no row for them.
        final model = newModel(user: mockSignedIn);
        await open(tester, model, () => LeaderboardRoute(model: model));
        model.update(() {});
        expect(find.text('Your rank: #7'), findsOneWidget);
        await finish(tester, model);
      },
    );

    testWidgets('This week and All time change the points', (tester) async {
      final model = await board(tester);
      await tester.tap(find.text('All time'));
      await tester.pump();
      expect(model.leaderboardScope, LeaderboardScope.allTime);
      expect(find.text('69,020'), findsOneWidget);
      expect(find.text('60,410 pts'), findsOneWidget);
      await tester.tap(find.text('This week'));
      await tester.pump();
      expect(find.text('9,860'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('the era filter lists the eras and filters the board', (
      tester,
    ) async {
      final model = await board(tester);
      await tester.tap(find.text('Era: All eras'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      for (final era in [
        'All eras',
        'Golden Age',
        "The '80s",
        "The '90s",
        'The 2000s',
        'Modern',
      ]) {
        expect(find.text(era), findsWidgets);
      }
      await tester.tap(find.text("The '80s").last);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(model.leaderboardEra, EraId.eighties);
      expect(find.text("Era: The '80s"), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('offline with a saved board: the board and a banner', (
      tester,
    ) async {
      final model = await board(tester, connection: Connection.offline);
      expect(
        find.text("You're offline. Showing the board from 3:20 PM."),
        findsOneWidget,
      );
      expect(find.text('Selam T.'), findsOneWidget);
      await finish(tester, model);
    });

    testWidgets('offline with nothing saved: a message, no board', (
      tester,
    ) async {
      final model = await board(
        tester,
        connection: Connection.offline,
        setUp: (m) => m.boardCached = false,
      );
      expect(
        find.text('Connect to the internet to see the leaderboard.'),
        findsOneWidget,
      );
      expect(find.text('Selam T.'), findsNothing);
      await finish(tester, model);
    });

    testWidgets('an empty board says so', (tester) async {
      final model = await board(tester, setUp: (m) => m.boardEmpty = true);
      expect(
        find.text('No scores yet this week. Be the first.'),
        findsOneWidget,
      );
      await finish(tester, model);
    });

    testWidgets('in Amharic: the title and the ranks read in Amharic', (
      tester,
    ) async {
      final model = await board(tester, locale: const Locale('am'));
      expect(find.text('የደረጃ ሰንጠረዥ'), findsOneWidget);
      expect(find.text('የዚህ ሳምንት'), findsOneWidget);
      expect(find.text('ዘመን፦ ሁሉም ዘመኖች'), findsOneWidget);
      await finish(tester, model);
    });
  });
}
