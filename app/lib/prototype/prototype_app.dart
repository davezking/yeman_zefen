import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'mock_data.dart';
import 'models.dart';
import 'prototype_lab.dart';
import 'prototype_flow.dart';
import 'prototype_model.dart';
import 'screens/home_screen.dart';
import 'screens/message_screens.dart';
import 'screens/onboarding_screens.dart';
import 'screens/mode_select_screen.dart';
import 'screens/offline_play_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';

/// The Phase 2 prototype: the hi-fi screens running on mock data, with a live
/// Amharic/English switch (Settings › Language). Run it with
/// `flutter run -t lib/main_prototype.dart`.
///
/// Play and Start play a game on a fake clock (no audio), then Results and the
/// leaderboard; Settings and Results open the sign-in sheets. The edge states
/// (first launch, consent, forced update, offline, out of songs, loading,
/// errors) are reached from the dev sheet. Only the About and privacy policy
/// rows are stubs.
class PrototypeApp extends StatefulWidget {
  const PrototypeApp({super.key, this.model, this.showAppStart = false});

  /// Tests pass their own model to start in a given state.
  final PrototypeModel? model;

  /// Show the app-start screen for a moment first.
  final bool showAppStart;

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  late final PrototypeModel _model = widget.model ?? PrototypeModel();
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _themes = <String, ThemeData>{};
  late bool _starting = widget.showAppStart;
  Timer? _startTimer;
  StreamSubscription<Toast>? _toasts;

  @override
  void initState() {
    super.initState();
    if (_starting) {
      _startTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _starting = false);
      });
    }
    _toasts = _model.toasts.listen(_showToast);
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _toasts?.cancel();
    if (widget.model == null) _model.dispose();
    super.dispose();
  }

  void _showToast(Toast toast) {
    final context = _navigator.currentContext;
    if (context == null) return;
    final l10n = AppLocalizations.of(context);
    final text = switch (toast) {
      OfflineToast() => l10n.offlineBannerShort,
      PendingToast(:final count) => l10n.offlinePending(count),
      SyncedToast() => l10n.offlineSynced,
      SyncFailedToast() => l10n.errorSync,
      SkippedToast() => l10n.feedbackSkipped,
    };
    _messenger.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// What the first page is: app start, the forced update, first launch, or Home.
  Widget _firstPage() {
    if (_starting) return const AppStartScreen();
    if (_model.updateRequired) {
      return ForcedUpdateScreen(
        ios: _model.showApple,
        onUpdate: _notBuilt,
        // Plays the songs on the phone, with no network features.
        onPlayOffline: () => _model.update(() {
          _model.updateRequired = false;
          _model.setConnection(Connection.offline);
        }),
      );
    }
    if (_model.firstLaunch) return _FirstLaunch(model: _model);
    return _HomeRoute(model: _model, onNotBuilt: _notBuilt);
  }

  ThemeData _themeFor(Locale locale) =>
      _themes.putIfAbsent(locale.languageCode, () => buildAppTheme(locale));

  /// Rows whose screens are not designed yet (privacy, about, ad choices).
  void _notBuilt() {
    _messenger.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('This screen is not part of the prototype.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final locale = Locale(_model.languageCode);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigator,
          scaffoldMessengerKey: _messenger,
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          locale: locale,
          theme: _themeFor(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrototypeLab(model: _model, navigator: _navigator, child: child!),
          home: _firstPage(),
        );
      },
    );
  }
}

class _HomeRoute extends StatelessWidget {
  const _HomeRoute({required this.model, required this.onNotBuilt});

  final PrototypeModel model;
  final VoidCallback onNotBuilt;

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
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
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _ModeRoute(model: model)),
        );
      },
      onLeaderboard: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LeaderboardRoute(model: model)),
      ),
      onSettings: () => Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) =>
              _SettingsRoute(model: model, onNotBuilt: onNotBuilt),
          transitionDuration: Duration.zero,
        ),
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
        onBack: () => Navigator.of(context).pop(),
        onNext: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _SetupRoute(model: model)),
        ),
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
          onBack: () => Navigator.of(context).pop(),
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
        onDeleteAccount: () => model.update(() => model.user = mockNewGuest),
        onOfflinePlay: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _OfflineRoute(model: model)),
        ),
        onAdPrivacy: () => showUmpForm(context, model),
        onPrivacy: onNotBuilt,
        onAbout: onNotBuilt,
        onHome: () => Navigator.of(context).pop(),
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
        onBack: () => Navigator.of(context).pop(),
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

/// First launch: the language, then the welcome, then round 1 of an
/// All eras · Intro · Easy game from the songs that come with the app.
class _FirstLaunch extends StatefulWidget {
  const _FirstLaunch({required this.model});

  final PrototypeModel model;

  @override
  State<_FirstLaunch> createState() => _FirstLaunchState();
}

class _FirstLaunchState extends State<_FirstLaunch> {
  bool _welcome = false;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (!_welcome) {
      return LanguageScreen(
        languageCode: model.languageCode,
        onLanguage: (code) => model.update(() => model.languageCode = code),
        onNext: () => setState(() => _welcome = true),
      );
    }
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
        _startGame(context, model);
      },
    );
  }
}

/// Plays a game with what the Play button starts. "Change era or mode" on its
/// Results goes back to Home and opens Mode select, whichever screen started it.
void _startGame(BuildContext context, PrototypeModel model) {
  // Offline with every song on the phone heard recently: nothing new to play.
  if (model.offline && model.allSongsPlayed) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OutOfSongsScreen(
          onBrowsePacks: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => _OfflineRoute(model: model),
            ),
          ),
          // A game that allows the recently played songs.
          onReplay: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => _roundPage(model)),
          ),
        ),
      ),
    );
    return;
  }
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => _roundPage(model)));
}

/// A game of what Play starts. "Change era or mode" on its Results goes back
/// to Home and opens Mode select, whichever screen started it.
Widget _roundPage(PrototypeModel model) => RoundRoute(
  model: model,
  onChangeSettings: (context) => Navigator.of(context)
    ..popUntil((route) => route.isFirst)
    ..push(MaterialPageRoute<void>(builder: (_) => _ModeRoute(model: model))),
);
