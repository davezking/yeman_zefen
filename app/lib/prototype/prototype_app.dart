import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'prototype_lab.dart';
import 'prototype_model.dart';
import 'prototype_router.dart';
import 'round_simulation.dart';

/// The Phase 2 prototype: the hi-fi screens running on mock data, with a live
/// Amharic/English switch (Settings › Language). Run it with
/// `flutter run -t lib/main_prototype.dart`.
///
/// Play and Start play a game on a fake clock (no audio), then Results and the
/// leaderboard; Settings and Results open the sign-in sheets. The edge states
/// (first launch, consent, forced update, offline, out of songs, loading,
/// errors) and every screen are reached from the hidden dev menu: put three
/// fingers on the screen at once (Ctrl+Shift+D on a keyboard). Only the About
/// and privacy policy rows are stubs.
class PrototypeApp extends StatefulWidget {
  const PrototypeApp({
    super.key,
    this.model,
    this.showAppStart = false,
    this.initialLocation,
    this.simulation,
  });

  /// Tests pass their own model to start in a given state.
  final PrototypeModel? model;

  /// Show the app-start screen for a moment first.
  final bool showAppStart;

  /// Open on this screen instead of Home.
  final String? initialLocation;

  /// Tests pass a seeded first game to know the answers.
  final RoundSimulation? simulation;

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  late final PrototypeModel _model = widget.model ?? PrototypeModel();
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _themes = <String, ThemeData>{};
  late final GoRouter _router = buildPrototypeRouter(
    _model,
    initialLocation:
        widget.initialLocation ??
        (widget.showAppStart ? ProtoPath.splash : ProtoPath.home),
    simulation: widget.simulation,
    navigatorKey: _navigator,
    onNotBuilt: _notBuilt,
  );
  StreamSubscription<Toast>? _toasts;

  @override
  void initState() {
    super.initState();
    _toasts = _model.toasts.listen(_showToast);
  }

  @override
  void dispose() {
    _toasts?.cancel();
    _router.dispose();
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
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _messenger,
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          locale: locale,
          theme: _themeFor(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: _router,
          builder: (context, child) => PrototypeLab(
            model: _model,
            router: _router,
            navigator: _navigator,
            child: child!,
          ),
        );
      },
    );
  }
}
