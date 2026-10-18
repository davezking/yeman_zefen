import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'mock_data.dart';
import 'models.dart';
import 'prototype_flow.dart';
import 'prototype_model.dart';
import 'prototype_paths.dart';
import 'round_simulation.dart';
import '../features/game/presentation/home_screen.dart';
import 'screens/message_screens.dart';
import '../features/game/presentation/mode_select_screen.dart';
import 'screens/offline_play_screen.dart';
import 'screens/onboarding_screens.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/game/presentation/setup_screen.dart';

export 'prototype_paths.dart';

/// The prototype's navigation: every screen on mock data, wired with
/// `go_router`. The screens take plain data and callbacks; this file and
/// `prototype_flow.dart` hold the glue that Phase 4 replaces with providers.
///
/// - First launch: Language → Welcome → the first round (no sign-up, no
///   download, no consent before it).
/// - Home → Mode → Setup → Round → (Ad consent) → Results → Leaderboard.
/// - Home / Results → Sign-in sheets (sheets, not routes).
/// - Home → Settings → Offline play (pack download, delete, clear cache).
/// - The forced update replaces whatever is open while it is required.
///
/// [simulation] is for tests: it is the first round's game, with known answers.
/// [onNotBuilt] answers the rows whose screens are not designed yet.
GoRouter buildPrototypeRouter(
  PrototypeModel model, {
  String initialLocation = ProtoPath.home,
  RoundSimulation? simulation,
  GlobalKey<NavigatorState>? navigatorKey,
  VoidCallback? onNotBuilt,
}) {
  RoundSimulation? pendingSimulation = simulation;
  final notBuilt = onNotBuilt ?? () {};

  Page<void> page(GoRouterState state, Widget child, {bool instant = false}) =>
      instant
      ? NoTransitionPage<void>(key: state.pageKey, child: child)
      : MaterialPage<void>(key: state.pageKey, child: child);

  /// [path] is the full path; a route under another takes the part after
  /// its parent's ([parent]), so `go` builds the parent's page beneath it.
  GoRoute route(
    String path,
    Widget Function(BuildContext context) builder, {
    bool instant = false,
    String? parent,
    List<GoRoute> routes = const [],
  }) => GoRoute(
    path: parent == null
        ? path
        : path.substring(parent == ProtoPath.home ? 1 : parent.length + 1),
    pageBuilder: (context, state) =>
        page(state, builder(context), instant: instant),
    routes: routes,
  );

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    // Only what the redirect reads: the model itself changes several times a
    // second while a pack downloads.
    refreshListenable: _RedirectInputs(model),
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (location == ProtoPath.splash) return null;
      // The forced update is the whole app while it is required, and goes
      // away when it is not (Play offline).
      if (model.updateGate) {
        return location == ProtoPath.update ? null : ProtoPath.update;
      }
      if (location == ProtoPath.update) return ProtoPath.home;
      if (model.firstLaunch && location == ProtoPath.home) {
        return ProtoPath.language;
      }
      return null;
    },
    routes: [
      route(ProtoPath.splash, (_) => const _SplashRoute()),
      route(ProtoPath.language, (_) => _LanguageRoute(model: model)),
      route(ProtoPath.welcome, (_) => _WelcomeRoute(model: model)),
      route(
        ProtoPath.update,
        (_) => ForcedUpdateScreen(
          ios: model.showApple,
          onUpdate: notBuilt,
          // Plays the songs on the phone, with no network features.
          onPlayOffline: () {
            model.playingOutdated = true;
            model.setConnection(Connection.offline);
          },
        ),
      ),
      // Everything else sits on Home, so `go` to any of them leaves Home
      // beneath and the system back gesture goes there instead of closing
      // the app.
      route(
        ProtoPath.home,
        (_) => _HomeRoute(model: model),
        routes: [
          route(
            ProtoPath.mode,
            (_) => _ModeRoute(model: model),
            parent: ProtoPath.home,
          ),
          route(
            ProtoPath.setup,
            (_) => _SetupRoute(model: model),
            parent: ProtoPath.home,
          ),
          route(ProtoPath.round, (_) {
            final sim = pendingSimulation;
            pendingSimulation = null;
            return RoundRoute(model: model, simulation: sim);
          }, parent: ProtoPath.home),
          route(
            ProtoPath.consent,
            (_) => ConsentRoute(model: model),
            parent: ProtoPath.home,
          ),
          route(
            ProtoPath.results,
            (_) => ResultsRoute(model: model),
            parent: ProtoPath.home,
          ),
          route(
            ProtoPath.leaderboard,
            (_) => LeaderboardRoute(model: model),
            parent: ProtoPath.home,
          ),
          route(
            ProtoPath.outOfSongs,
            (context) => OutOfSongsScreen(
              onBrowsePacks: () =>
                  context.pushReplacement(ProtoPath.offlinePlay),
              // A game that allows the recently played songs.
              onReplay: () => context.pushReplacement(ProtoPath.round),
            ),
            parent: ProtoPath.home,
          ),
          route(
            ProtoPath.error,
            (context) => ErrorScreen(onRetry: context.popOrHome),
            parent: ProtoPath.home,
          ),
          // Settings is a tab: it replaces Home without a slide.
          route(
            ProtoPath.settings,
            (_) => _SettingsRoute(model: model, onNotBuilt: notBuilt),
            instant: true,
            parent: ProtoPath.home,
            routes: [
              route(
                ProtoPath.offlinePlay,
                (_) => _OfflineRoute(model: model),
                parent: ProtoPath.settings,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Tells the router when the forced update or the first launch turns on or
/// off. It lives as long as the model it listens to.
class _RedirectInputs extends ChangeNotifier {
  _RedirectInputs(this.model) : _last = (model.updateGate, model.firstLaunch) {
    model.addListener(_check);
  }

  final PrototypeModel model;
  (bool, bool) _last;

  void _check() {
    final now = (model.updateGate, model.firstLaunch);
    if (now == _last) return;
    _last = now;
    notifyListeners();
  }
}

/// The Play button: a game with the settings last used. Offline with every
/// song on the phone heard recently, there is nothing new to play.
void _startGame(BuildContext context, PrototypeModel model) {
  if (model.offline && model.allSongsPlayed) {
    context.push(ProtoPath.outOfSongs);
  } else {
    context.push(ProtoPath.round);
  }
}

/// App start: the wordmark for a moment, then Home (or the first launch).
class _SplashRoute extends StatefulWidget {
  const _SplashRoute();

  @override
  State<_SplashRoute> createState() => _SplashRouteState();
}

class _SplashRouteState extends State<_SplashRoute> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) context.go(ProtoPath.home);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const AppStartScreen();
}

/// First launch, step 1. The language is chosen as soon as it is tapped.
class _LanguageRoute extends StatelessWidget {
  const _LanguageRoute({required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => LanguageScreen(
      languageCode: model.languageCode,
      onLanguage: (code) => model.update(() => model.languageCode = code),
      onNext: () => context.go(ProtoPath.welcome),
    ),
  );
}

/// First launch, step 2: Start goes straight into round 1 of an
/// All eras · Intro · Easy game from the songs that come with the app.
class _WelcomeRoute extends StatelessWidget {
  const _WelcomeRoute({required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return WelcomeScreen(
      sampleAnswers: [
        for (final t in mockTracks.take(1)) t.artist(locale),
        mockWelcomeSecondAnswer(locale),
      ],
      onStart: () {
        model.update(() {
          model.quickPlay = const PlaySettings();
          model.firstLaunch = false;
        });
        // Home is beneath the game.
        context.go(ProtoPath.round);
      },
    );
  }
}

class _HomeRoute extends StatelessWidget {
  const _HomeRoute({required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => HomeScreen(
        user: model.user,
        quickPlay: model.quickPlay,
        offline: model.offline,
        hasDownloadedPacks: model.hasDownloadedPacks,
        builtInSongCount: mockBuiltInSongCount,
        onPlay: () => _startGame(context, model),
        onModeSelected: (mode) {
          model.update(
            () => model.quickPlay = model.quickPlay.copyWith(mode: mode),
          );
          context.push(ProtoPath.mode);
        },
        onLeaderboard: () => context.push(ProtoPath.leaderboard),
        onSettings: () => context.push(ProtoPath.settings),
      ),
    );
  }
}

class _ModeRoute extends StatelessWidget {
  const _ModeRoute({required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => ModeSelectScreen(
        mode: model.quickPlay.mode,
        guess: model.quickPlay.guess,
        onModeChanged: (m) => model.update(
          () => model.quickPlay = model.quickPlay.copyWith(mode: m),
        ),
        onGuessChanged: (g) => model.update(
          () => model.quickPlay = model.quickPlay.copyWith(guess: g),
        ),
        onBack: context.popOrHome,
        onNext: () => context.push(ProtoPath.setup),
      ),
    );
  }
}

class _SetupRoute extends StatelessWidget {
  const _SetupRoute({required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final s = model.quickPlay;
        return SetupScreen(
          mode: s.mode,
          generationId: s.generationId,
          genre: s.genre,
          difficulty: s.difficulty,
          disabledEras: model.disabledEras,
          tooFewSongs: model.tooFewSongsFor(s),
          onEra: (id) => model.update(
            () => model.quickPlay = s.copyWith(generationId: id),
          ),
          onGenre: (g) =>
              model.update(() => model.quickPlay = s.copyWith(genre: g)),
          onDifficulty: (d) =>
              model.update(() => model.quickPlay = s.copyWith(difficulty: d)),
          onBack: context.popOrHome,
          onStart: () => _startGame(context, model),
        );
      },
    );
  }
}

class _SettingsRoute extends StatelessWidget {
  const _SettingsRoute({required this.model, required this.onNotBuilt});

  final PrototypeModel model;
  final VoidCallback onNotBuilt;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => SettingsScreen(
        languageCode: model.languageCode,
        soundOn: model.soundOn,
        hapticsOn: model.hapticsOn,
        user: model.user,
        offlinePackCount: model.installedPackCount,
        offlineSizeMb: model.installedSizeMb,
        offlineUpdateAvailable: model.updateAvailable,
        version: mockAppVersion,
        onLanguage: (code) => model.update(() => model.languageCode = code),
        onSound: (v) => model.update(() => model.soundOn = v),
        onHaptics: (v) => model.update(() => model.hapticsOn = v),
        onSignIn: () => showSignInFlow(context, model),
        onSignOut: () => model.update(() => model.user = mockGuest),
        // The account and its scores are gone: a guest who has not played.
        onDeleteAccount: () => model.update(() => model.user = mockNewGuest),
        onOfflinePlay: () => context.push(ProtoPath.offlinePlay),
        onAdPrivacy: () => showUmpForm(context, model),
        onPrivacy: onNotBuilt,
        onAbout: onNotBuilt,
        onHome: context.popOrHome,
        onPlay: () => _startGame(context, model),
      ),
    );
  }
}

/// Settings › Offline play. With slow lists on, the packs to download take 2 s
/// to appear (a skeleton shows meanwhile).
class _OfflineRoute extends StatefulWidget {
  const _OfflineRoute({required this.model});

  final PrototypeModel model;

  @override
  State<_OfflineRoute> createState() => _OfflineRouteState();
}

class _OfflineRouteState extends State<_OfflineRoute> {
  late bool _loading = widget.model.slowLists && !widget.model.offline;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_loading) {
      _timer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => OfflinePlayScreen(
        loadingPacks: _loading,
        wifiOnly: model.wifiOnly,
        mobilePrefetch: model.mobilePrefetch,
        cache: model.cache,
        builtInSongCount: mockBuiltInSongCount,
        packs: model.packs,
        connection: model.connection,
        onBack: context.popOrHome,
        onWifiOnly: (v) => model.update(() => model.wifiOnly = v),
        onMobilePrefetch: (v) => model.update(() => model.mobilePrefetch = v),
        onClearCache: () => model.update(
          () => model.cache = CacheUsage(usedMb: 0, capMb: model.cache.capMb),
        ),
        onDownload: model.download,
        onCancel: model.cancel,
        onRetry: model.download,
        onRemove: model.remove,
      ),
    );
  }
}
