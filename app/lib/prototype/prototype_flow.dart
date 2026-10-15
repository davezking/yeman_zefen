import 'dart:async';

import 'package:flutter/material.dart';

import '../core/widgets/widgets.dart';
import '../l10n/app_localizations.dart';
import 'models.dart';
import 'prototype_model.dart';
import 'round_simulation.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/results_screen.dart';
import 'screens/round_screen.dart';
import 'screens/sign_in_sheet.dart';

/// The routes that play a game on mock data: the round (on a fake clock),
/// Results, the leaderboard, and the sign-in sheets. They wire the screens to
/// [PrototypeModel] and the simulation; the screens themselves know nothing of
/// either.

// ---------------------------------------------------------------------------
// The round

/// Plays one game of [PrototypeModel.quickPlay]. When it ends it is replaced
/// by [ResultsRoute]; "Leave" pops it.
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
      );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sim.addListener(_changed);
  }

  @override
  void dispose() {
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
    if (_sim.left) {
      _done = true;
      Navigator.of(context).pop();
    } else if (_sim.finished) {
      _done = true;
      final results = widget.model.finishGame(
        _sim.results,
        _sim.score,
        _sim.newBest,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultsRoute(
            model: widget.model,
            results: results,
            onPlayAgain: (context) => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => RoundRoute(model: widget.model),
              ),
            ),
          ),
        ),
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

/// Results for a finished game. The score starts as the phone's own count and,
/// online, is "confirmed" by the fake server a moment later. After a guest's
/// 5th game the sign-in sheet opens over it.
class ResultsRoute extends StatefulWidget {
  const ResultsRoute({
    super.key,
    required this.model,
    required this.results,
    required this.onPlayAgain,
  });

  final PrototypeModel model;
  final ResultsView results;

  /// Starts another game with the same settings (replacing this route).
  final void Function(BuildContext context) onPlayAgain;

  @override
  State<ResultsRoute> createState() => _ResultsRouteState();
}

class _ResultsRouteState extends State<ResultsRoute> {
  late ScoreSync _sync = widget.results.sync;
  Timer? _server;

  @override
  void initState() {
    super.initState();
    if (_sync == ScoreSync.provisional) {
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
    final r = widget.results;
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
        onPlayAgain: () => widget.onPlayAgain(context),
        onChange: () => Navigator.of(context).pop(),
        onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
        onSignIn: () => showSignInFlow(context, widget.model),
        onLeaderboard: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LeaderboardRoute(model: widget.model),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leaderboard

class LeaderboardRoute extends StatelessWidget {
  const LeaderboardRoute({super.key, required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => LeaderboardScreen(
        view: model.leaderboard,
        onBack: () => Navigator.of(context).pop(),
        onScope: (s) => model.update(() => model.leaderboardScope = s),
        onEra: (id) => model.update(() => model.leaderboardEra = id),
        onSignIn: () => showSignInFlow(context, model),
      ),
    );
  }
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
    } else if (password.length < 6 && !_creating) {
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
