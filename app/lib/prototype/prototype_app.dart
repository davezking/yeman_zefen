import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'mock_data.dart';
import 'models.dart';
import 'prototype_lab.dart';
import 'prototype_model.dart';
import 'screens/home_screen.dart';
import 'screens/mode_select_screen.dart';
import 'screens/offline_play_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';

/// The Phase 2 prototype: the hi-fi screens running on mock data, with a live
/// Amharic/English switch (Settings › Language). Run it with
/// `flutter run -t lib/main_prototype.dart`.
///
/// Play and Start stop at a message: the round screens are the next task.
class PrototypeApp extends StatefulWidget {
  const PrototypeApp({super.key, this.model});

  /// Tests pass their own model to start in a given state.
  final PrototypeModel? model;

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  late final PrototypeModel _model = widget.model ?? PrototypeModel();
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _themes = <String, ThemeData>{};

  @override
  void dispose() {
    if (widget.model == null) _model.dispose();
    super.dispose();
  }

  ThemeData _themeFor(Locale locale) =>
      _themes.putIfAbsent(locale.languageCode, () => buildAppTheme(locale));

  void _roundComesNext() {
    _messenger.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('The round screens come in the next task.'),
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
          home: _HomeRoute(
            model: _model,
            onPlay: _roundComesNext,
            onStart: _roundComesNext,
          ),
        );
      },
    );
  }
}

class _HomeRoute extends StatelessWidget {
  const _HomeRoute({
    required this.model,
    required this.onPlay,
    required this.onStart,
  });

  final PrototypeModel model;
  final VoidCallback onPlay;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      user: model.user,
      quickPlay: model.quickPlay,
      offline: model.offline,
      hasDownloadedPacks: model.hasDownloadedPacks,
      builtInSongCount: mockBuiltInSongCount,
      onPlay: onPlay,
      onModeSelected: (mode) {
        model.update(
          () => model.quickPlay = model.quickPlay.copyWith(mode: mode),
        );
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ModeRoute(model: model, onStart: onStart),
          ),
        );
      },
      onLeaderboard: onPlay,
      onSettings: () => Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) =>
              _SettingsRoute(model: model, onPlay: onPlay),
          transitionDuration: Duration.zero,
        ),
      ),
    );
  }
}

class _ModeRoute extends StatelessWidget {
  const _ModeRoute({required this.model, required this.onStart});

  final PrototypeModel model;
  final VoidCallback onStart;

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
          MaterialPageRoute<void>(
            builder: (_) => _SetupRoute(model: model, onStart: onStart),
          ),
        ),
      ),
    );
  }
}

class _SetupRoute extends StatelessWidget {
  const _SetupRoute({required this.model, required this.onStart});

  final PrototypeModel model;
  final VoidCallback onStart;

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
          onStart: onStart,
        );
      },
    );
  }
}

class _SettingsRoute extends StatelessWidget {
  const _SettingsRoute({required this.model, required this.onPlay});

  final PrototypeModel model;
  final VoidCallback onPlay;

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
        onSignIn: () => model.update(() => model.user = mockSignedIn),
        onSignOut: () => model.update(() => model.user = mockGuest),
        onDeleteAccount: () => model.update(() => model.user = mockNewGuest),
        onOfflinePlay: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _OfflineRoute(model: model)),
        ),
        onAdPrivacy: onPlay,
        onPrivacy: onPlay,
        onAbout: onPlay,
        onHome: () => Navigator.of(context).pop(),
        onPlay: onPlay,
      ),
    );
  }
}

class _OfflineRoute extends StatelessWidget {
  const _OfflineRoute({required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => OfflinePlayScreen(
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
