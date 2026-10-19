import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/widgets.dart';
import '../l10n/app_localizations.dart';
import 'mock_data.dart';
import 'models.dart';
import 'prototype_model.dart';
import 'prototype_paths.dart';
import 'round_simulation.dart';
import '../features/leaderboard/ui/leaderboard_screen.dart';
import 'screens/message_screens.dart';
import '../features/game/presentation/results_screen.dart';
import '../features/game/presentation/round_screen.dart';
import '../features/account/ui/sign_in_sheet.dart';

/// The routes that play a game on mock data: the round (on a fake clock),
/// Results, the leaderboard, and the sign-in sheets. They wire the screens to
/// [PrototypeModel] and the simulation; the screens themselves know nothing of
/// either.

// ---------------------------------------------------------------------------
// The round

/// Plays one game of [PrototypeModel.quickPlay]. When it ends it is replaced
/// by Results (after Ad consent, where that is due); "Leave" goes back.
class RoundRoute extends StatefulWidget {
  const RoundRoute({super.key, required this.model, this.simulation});

  final PrototypeModel model;

  /// Tests pass a seeded game to know the answers.
  final RoundSimulation? simulation;

  @override
  State<RoundRoute> createState() => _RoundRouteState();
}

class _RoundRouteState extends State<RoundRoute> with WidgetsBindingObserver {
  late final RoundSimulation _sim =
      widget.simulation ??
      RoundSimulation(
        settings: widget.model.quickPlay,
        bestScore: widget.model.user.bestScore,
        clipLoadTime: widget.model.clipLoadTime,
      );
  bool _done = false;
  int _skipped = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sim.addListener(_changed);
    widget.model.roundsOnScreen++;
  }

  @override
  void dispose() {
    widget.model.roundsOnScreen--;
    WidgetsBinding.instance.removeObserver(this);
    _sim.removeListener(_changed);
    _sim.dispose();
    super.dispose();
  }

  // The clip and the timer stop while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _sim.setBackgrounded(state != AppLifecycleState.resumed);

  void _changed() {
    if (!mounted || _done) return;
    if (_sim.skipped > _skipped) {
      _skipped = _sim.skipped;
      widget.model.toast(const SkippedToast());
    }
    if (_sim.left) {
      _done = true;
      context.popOrHome();
    } else if (_sim.finished) {
      _done = true;
      final model = widget.model;
      model.finishGame(_sim.results, _sim.score, _sim.newBest);
      // After the first finished game, and only where consent is required,
      // ad consent comes before Results (and again until it is answered).
      final askConsent = model.consentRequired && !model.consentDone;
      context.pushReplacement(
        askConsent ? ProtoPath.consent : ProtoPath.results,
      );
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _sim.requestLeave();
      },
      child: RoundScreen(
        view: _sim.view,
        onAnswer: _sim.answer,
        onHint: _sim.requestHint,
        onContinue: _sim.tapContinue,
        onLeaveRequested: _sim.requestLeave,
        onLeaveConfirmed: _sim.confirmLeave,
        onLeaveCancelled: _sim.cancelLeave,
        onWatchHintAd: _sim.watchHintAd,
        onDeclineHint: _sim.declineHint,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results

/// Results for the last finished game (a sample game when none was played).
/// The score starts as the phone's own count and, online, is "confirmed" by
/// the fake server a moment later. After a guest's 5th game the sign-in sheet
/// opens over it.
class ResultsRoute extends StatefulWidget {
  const ResultsRoute({super.key, required this.model});

  final PrototypeModel model;

  @override
  State<ResultsRoute> createState() => _ResultsRouteState();
}

class _ResultsRouteState extends State<ResultsRoute> {
  late final ResultsView _results =
      widget.model.lastResults ?? mockResults(user: widget.model.user);
  late ScoreSync _sync = _results.sync;
  Timer? _server;

  @override
  void initState() {
    super.initState();
    // A state forced from the dev menu stays as it is.
    if (_sync == ScoreSync.provisional && widget.model.forcedSync == null) {
      _server = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _sync = ScoreSync.synced);
      });
    }
    if (widget.model.gamesFinished == 5 && widget.model.user.isGuest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showSignInFlow(context, widget.model);
      });
    }
  }

  @override
  void dispose() {
    _server?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _results;
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) => ResultsScreen(
        view: ResultsView(
          score: r.score,
          rounds: r.rounds,
          user: widget.model.user,
          newBest: r.newBest,
          sync: _sync,
        ),
        // The same settings again, in place of this screen.
        onPlayAgain: () => context.pushReplacement(ProtoPath.round),
        // The era and mode choices, with Home behind them.
        onChange: () => context.go(ProtoPath.mode),
        onHome: () => context.go(ProtoPath.home),
        onSignIn: () => showSignInFlow(context, widget.model),
        onLeaderboard: () => context.push(ProtoPath.leaderboard),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leaderboard

/// The leaderboard. It "loads" for a moment (2 s with slow lists on, when a
/// skeleton shows), and can fail once to show the error screen.
class LeaderboardRoute extends StatefulWidget {
  const LeaderboardRoute({super.key, required this.model});

  final PrototypeModel model;

  @override
  State<LeaderboardRoute> createState() => _LeaderboardRouteState();
}

class _LeaderboardRouteState extends State<LeaderboardRoute> {
  bool _loading = false;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _load() {
    final model = widget.model;
    if (model.offline) return;
    if (model.boardFails) {
      model.boardFails = false;
      setState(() => _failed = true);
      return;
    }
    if (!model.slowLists) return;
    setState(() {
      _failed = false;
      _loading = true;
    });
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _change(void Function() change) {
    widget.model.update(change);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (_failed) {
      return ErrorScreen(
        onBack: context.popOrHome,
        onRetry: () {
          setState(() => _failed = false);
          _load();
        },
      );
    }
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final board = model.leaderboard;
        return LeaderboardScreen(
          view: _loading
              ? LeaderboardView(
                  scope: board.scope,
                  generationId: board.generationId,
                  entries: const [],
                  user: board.user,
                  state: LeaderboardState.loading,
                )
              : board,
          onBack: context.popOrHome,
          onScope: (s) => _change(() => model.leaderboardScope = s),
          onEra: (id) => _change(() => model.leaderboardEra = id),
          onSignIn: () => showSignInFlow(context, model),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Ad consent

/// Ad consent after the first finished game: the explanation, then Google's
/// form (a placeholder here), then Results.
class ConsentRoute extends StatelessWidget {
  const ConsentRoute({super.key, required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) {
    // Consent has to be answered: back does not skip it (or Results).
    return PopScope(
      canPop: false,
      child: ConsentScreen(
        onContinue: () async {
          await showUmpForm(context, model);
          // Closing the form without answering stays here.
          if (!context.mounted || !model.consentDone) return;
          context.pushReplacement(ProtoPath.results);
        },
      ),
    );
  }
}

/// Google's consent form (UMP), as a placeholder sheet. It is also what
/// Settings › Ad privacy choices opens.
Future<void> showUmpForm(BuildContext context, PrototypeModel model) {
  return showAppBottomSheet<void>(
    context,
    semanticLabel: AppLocalizations.of(context).settingsAdPrivacy,
    builder: (sheetContext) => UmpFormPlaceholder(
      onDone: () {
        model.consentDone = true;
        Navigator.of(sheetContext).pop();
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Sign in

/// Opens the sign-in sheet: the choice of account, the email form, and the
/// display-name step. Signing in always succeeds in the prototype, unless the
/// dev sheet says the next one fails.
Future<void> showSignInFlow(BuildContext context, PrototypeModel model) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  return showAppBottomSheet<void>(
    context,
    semanticLabel: l10n.authPromptTitle,
    builder: (_) => _SignInFlow(
      model: model,
      onSignedIn: (name) => messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.authSignedIn(name)))),
    ),
  );
}

enum _Step { choose, email, name }

class _SignInFlow extends StatefulWidget {
  const _SignInFlow({required this.model, required this.onSignedIn});

  final PrototypeModel model;
  final ValueChanged<String> onSignedIn;

  @override
  State<_SignInFlow> createState() => _SignInFlowState();
}

class _SignInFlowState extends State<_SignInFlow> {
  _Step _step = _Step.choose;
  SignInStatus _status = SignInStatus.idle;
  SignInProvider? _with;
  bool _creating = false;
  EmailError _emailError = EmailError.none;
  NameError _nameError = NameError.none;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The provider answers after a moment: it works, or the scores cannot be
  /// attached yet.
  void _signIn(SignInProvider provider) {
    setState(() {
      _status = SignInStatus.signingIn;
      _with = provider;
      _emailError = EmailError.none;
    });
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final fails = widget.model.nextSignIn == SignInOutcome.linkFails;
      widget.model.nextSignIn = SignInOutcome.works;
      setState(() {
        if (fails) {
          _status = SignInStatus.linkFailed;
          _step = _Step.choose;
        } else {
          _status = SignInStatus.idle;
          _step = _Step.name;
        }
      });
    });
  }

  void _submitEmail(String email, String password) {
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _emailError = EmailError.email);
    } else if (password.length < 6) {
      setState(() => _emailError = EmailError.password);
    } else {
      _signIn(SignInProvider.email);
    }
  }

  void _saveName(String raw) {
    final name = raw.trim();
    if (name.length < 2) {
      setState(() => _nameError = NameError.tooShort);
    } else if (name.toLowerCase() == 'selam t.') {
      setState(() => _nameError = NameError.taken);
    } else {
      final before = widget.model.user;
      widget.model.update(
        () => widget.model.user = UserInfo.signedIn(
          displayName: name,
          bestScore: before.bestScore,
          weeklyRank: 7,
        ),
      );
      widget.onSignedIn(name);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.choose:
        return SignInSheet(
          showApple: widget.model.showApple,
          status: _status,
          signingInWith: _with,
          onProvider: (p) => p == SignInProvider.email
              ? setState(() {
                  _step = _Step.email;
                  _status = SignInStatus.idle;
                })
              : _signIn(p),
          onNotNow: () => Navigator.of(context).pop(),
        );
      case _Step.email:
        return EmailSignInSheet(
          creating: _creating,
          error: _emailError,
          busy: _status == SignInStatus.signingIn,
          onToggleCreate: () => setState(() {
            _creating = !_creating;
            _emailError = EmailError.none;
          }),
          onSubmit: _submitEmail,
          onForgot: () {},
          onBack: () => setState(() {
            _step = _Step.choose;
            _emailError = EmailError.none;
          }),
        );
      case _Step.name:
        return DisplayNameSheet(error: _nameError, onSave: _saveName);
    }
  }
}
