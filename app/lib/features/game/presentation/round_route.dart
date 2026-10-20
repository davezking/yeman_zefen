import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ads/ads_providers.dart';
import '../../../core/ads/consent_service.dart';
import '../../../core/l10n/display_name.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/models.dart' as proto;
import '../../../prototype/screens/message_screens.dart' show OutOfSongsScreen;
import '../../settings/application/settings_providers.dart';
import '../application/session_controller.dart';
import '../application/session_state.dart';
import 'round_screen.dart';
import 'session_texts.dart';

/// The round with real data: the engine's state drawn by the approved [RoundScreen].
///
/// The engine owns the clock and the rules. This keeps what only a screen can know: when the app
/// goes to the background, whether the "Leave this game?" question is open, and the clock that
/// makes the countdown move (read from the engine's own start time, so it cannot drift from it).
class RoundRoute extends ConsumerStatefulWidget {
  const RoundRoute({super.key});

  @override
  ConsumerState<RoundRoute> createState() => _RoundRouteState();
}

class _RoundRouteState extends ConsumerState<RoundRoute> with WidgetsBindingObserver {
  Timer? _tick;
  var _leaveOpen = false;

  /// The session ended while the "Leave this game?" question was open: the results wait for the
  /// answer instead of replacing the question.
  var _resultsWaiting = false;

  /// The last round that was on screen, kept to draw behind the question when the session ends.
  SessionState? _lastPlaying;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The countdown and the "Tap to continue" seconds move on the design's tick.
    _tick = Timer.periodic(MotionTokens.durationTimerTick, (_) {
      if (mounted && _clockRuns(ref.read(sessionControllerProvider))) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Whether anything on screen moves with time now.
  bool _clockRuns(SessionState state) {
    final round = state.round;
    if (round == null || _leaveOpen) return false;
    return round.phase == RoundPhase.answering || (round.phase == RoundPhase.feedback && !round.isCorrect);
  }

  SessionController get _controller => ref.read(sessionControllerProvider.notifier);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Going to the background pauses the round (audio and answer clock). Coming back shows the
    // paused notice, and the clip plays again when the player resumes.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _controller.pauseForBackground();
    }
  }

  /// The back button or the close icon: the round stops under the question, as the design says.
  void _requestLeave() {
    if (_leaveOpen) return;
    // Before the first round there is no game to lose, and no screen to ask on.
    if (ref.read(sessionControllerProvider).round == null) return _leave();
    _controller.pauseForBackground();
    setState(() => _leaveOpen = true);
  }

  void _keepPlaying() {
    setState(() => _leaveOpen = false);
    if (_resultsWaiting) {
      _resultsWaiting = false;
      _goToResults();
      return;
    }
    _controller.resume();
  }

  /// The game is over. Where Google says ad consent is required, the consent screen comes first
  /// (H15); on iOS elsewhere, Apple's tracking question shows over Results.
  void _goToResults() {
    final consent = ref.read(consentServiceProvider);
    switch (consent.askAfterGame) {
      case ConsentAsk.form:
        context.go('/consent');
      case ConsentAsk.tracking:
        unawaited(consent.requestTracking());
        context.go('/results');
      case ConsentAsk.none:
        context.go('/results');
    }
  }

  void _tellHint(HintNotice notice) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(notice == HintNotice.notFinished ? l10n.adNotFinished : l10n.adUnavailable)),
      );
  }

  void _leave() {
    _controller.leave();
    context.go('/setup');
  }

  void _haptic(RoundView round) {
    if (!ref.read(hapticsOnProvider)) return;
    if (round.timedOut || !round.isCorrect) {
      unawaited(HapticFeedback.heavyImpact());
    } else {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider, (previous, next) {
      if (next.phase == SessionPhase.finished && previous?.phase != SessionPhase.finished) {
        if (_leaveOpen) {
          _resultsWaiting = true;
        } else {
          _goToResults();
        }
      }
      final round = next.round;
      final before = previous?.round;
      if (round == null) return;
      final notice = round.hintNotice;
      if (notice != null && round.hintNoticeId != before?.hintNoticeId) _tellHint(notice);
      // The result of an answer: a tap you can feel, if the player wants one.
      if (round.phase == RoundPhase.feedback && (before?.phase != RoundPhase.feedback || before?.number != round.number)) {
        _haptic(round);
      }
      // A new round started while the question is open: it waits too.
      if (_leaveOpen && round.phase == RoundPhase.answering && before?.phase != RoundPhase.answering) {
        _controller.pauseForBackground();
      }
    });
    final l10n = AppLocalizations.of(context);
    var state = ref.watch(sessionControllerProvider);
    if (state.phase == SessionPhase.playing && state.round != null) _lastPlaying = state;
    // The session ended under the open question: the round stays behind it until it is answered.
    if (_leaveOpen && state.phase == SessionPhase.finished && _lastPlaying != null) state = _lastPlaying!;
    final over = state.phase == SessionPhase.failed || state.phase == SessionPhase.idle;
    final round = state.round;

    final Widget body;
    if (state.phase == SessionPhase.outOfSongs) {
      body = OutOfSongsScreen(
        onBrowsePacks: () {
          _controller.leave();
          context.go('/packs');
        },
        onReplay: _controller.playAgain,
      );
    } else if (state.phase == SessionPhase.playing && round != null) {
      body = RoundScreen(
        view: screenViewOf(
          state,
          l10n: l10n,
          locale: Localizations.localeOf(context),
          nowMs: ref.read(sessionEnvironmentProvider).monotonicMs(),
          leaveOpen: _leaveOpen,
          rewardedReady: ref.watch(rewardedReadyProvider),
        ),
        onAnswer: (index) {
          if (!_leaveOpen && index >= 0 && index < round.options.length) _controller.answer(round.options[index].id);
        },
        onHint: _controller.openHint,
        onContinue: _controller.skipFeedback,
        onLeaveRequested: _requestLeave,
        onLeaveConfirmed: _leave,
        onLeaveCancelled: _keepPlaying,
        onWatchHintAd: _controller.watchHintAd,
        onDeclineHint: _controller.declineHint,
        onResume: _controller.resume,
      );
    } else {
      body = Scaffold(
        appBar: AppBar(
          title: Text(l10n.roundGetReady),
          leading: IconButton(
            tooltip: l10n.roundLeave,
            icon: const Icon(Icons.close),
            onPressed: () => over ? context.go('/setup') : _requestLeave(),
          ),
        ),
        body: switch (state.phase) {
          SessionPhase.failed => _Message(
              text: state.error == null ? l10n.roundCouldNotStart : l10n.sessionErrorText(state.error!),
              action: FilledButton(onPressed: () => context.go('/setup'), child: Text(l10n.navBack)),
            ),
          SessionPhase.idle => _Message(
              text: l10n.roundNoGame,
              action: FilledButton(onPressed: () => context.go('/setup'), child: Text(l10n.roundStartGame)),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      );
    }

    return PopScope(
      canPop: over,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestLeave();
      },
      child: body,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.action});

  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, key: const Key('message'), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action,
            ],
          ),
        ),
      );
}

/// What the approved round screen draws for the engine's [state] at monotonic time [nowMs].
///
/// Names are resolved to [locale]'s script here, on every build, so a language switch changes the
/// screen at once. [leaveOpen] puts the "Leave this game?" question over the round, with the
/// timer stopped. [rewardedReady] says a rewarded ad is loaded, so the hint can be offered.
proto.RoundView screenViewOf(
  SessionState state, {
  required AppLocalizations l10n,
  required Locale locale,
  required int nowMs,
  bool leaveOpen = false,
  bool rewardedReady = false,
}) {
  final round = state.round!;
  final config = state.config;
  final kind = proto.QuestionKind.values.byName(round.kind.name);
  final interrupted = round.phase == RoundPhase.interrupted;

  // The screen shows a track's title or artist by script; the name is already the right one.
  proto.Track named(DisplayName song, DisplayName artist, {required int id, int generationId = 0}) {
    final title = l10n.nameOf(song, locale);
    final singer = l10n.nameOf(artist, locale);
    return proto.Track(
      id: '$id',
      titleAm: title,
      titleLatin: title,
      artistAm: singer,
      artistLatin: singer,
      generationId: generationId,
      genre: proto.Genre.any,
    );
  }

  final options = [
    for (final o in round.options)
      if (kind == proto.QuestionKind.era)
        // Which Era?: the options are eras, which the screen names in the UI language.
        proto.RoundOption.era(o.id)
      else
        proto.RoundOption.track(
          kind == proto.QuestionKind.artist
              ? named(const DisplayName(), o.name, id: o.id)
              : named(o.name, const DisplayName(), id: o.id),
        ),
  ];
  int indexOf(int? id) => id == null ? -1 : round.options.indexWhere((o) => o.id == id);

  final proto.RoundPhase phase = switch (round.phase) {
    RoundPhase.loading => proto.RoundPhase.loading,
    RoundPhase.answering || RoundPhase.interrupted => proto.RoundPhase.answering,
    RoundPhase.feedback => round.timedOut
        ? proto.RoundPhase.timeout
        : round.isCorrect
            ? proto.RoundPhase.correct
            : proto.RoundPhase.wrong,
  };

  // What is left of the answer window. While running it comes from the engine's clock; while
  // paused or answered it is what the engine says was left.
  final window = round.windowMs;
  final clockStart = round.answerClockStartMs;
  final leftMs = (round.phase == RoundPhase.answering && clockStart != null && !leaveOpen
          ? window - (nowMs - clockStart)
          : round.remainingMs)
      .clamp(0, window);

  final sheetOpenedAt = round.hintSheetOpenedAtMs;
  final sheetLeftMs = sheetOpenedAt == null ? 0 : (round.hintSheetMs - (nowMs - sheetOpenedAt)).clamp(0, round.hintSheetMs);

  final feedbackStart = round.feedbackStartedAtMs;
  final feedbackLeftMs = feedbackStart == null ? 0 : (round.feedbackMs - (nowMs - feedbackStart)).clamp(0, round.feedbackMs);

  final stopped = interrupted || leaveOpen || sheetOpenedAt != null || state.ad != RoundAd.none;
  return proto.RoundView(
    roundNumber: round.number,
    totalRounds: round.total,
    score: round.score,
    eraFilterId: config?.generationId ?? proto.EraId.all,
    // Which Era? always plays 10 s, which is what Easy means.
    difficulty: config == null
        ? proto.Difficulty.medium
        : kind == proto.QuestionKind.era
            ? proto.Difficulty.easy
            : proto.Difficulty.values.byName(config.difficulty.name),
    kind: kind,
    options: options,
    correctIndex: indexOf(round.correctId).clamp(0, options.isEmpty ? 0 : options.length - 1),
    // For the reveal. In Which Era? that is the song's era, which is the correct answer.
    track: named(round.trackName, round.artistName, id: 0, generationId: kind == proto.QuestionKind.era ? round.correctId ?? 0 : 0),
    phase: phase,
    clipPlaying: round.clipPlaying && !stopped,
    timeFraction: window == 0 ? 0 : leftMs / window,
    secondsLeft: (leftMs / 1000).ceil(),
    timerPaused: stopped,
    pickedIndex: indexOf(round.chosenId) < 0 ? null : indexOf(round.chosenId),
    removed: {for (final id in round.removedIds) if (indexOf(id) >= 0) indexOf(id)},
    hintAvailable: rewardedReady && round.hintOffered && state.ad == RoundAd.none,
    hintUsed: round.hintUsed,
    points: round.points ?? 0,
    speedBonus: round.speedBonus,
    valid: round.valid,
    feedbackSecondsLeft: (feedbackLeftMs / 1000).ceil(),
    overlay: leaveOpen
        ? proto.RoundOverlay.leaveDialog
        : interrupted
            ? proto.RoundOverlay.paused
            : switch (state.ad) {
                RoundAd.interstitial => proto.RoundOverlay.interstitial,
                RoundAd.rewarded => proto.RoundOverlay.rewardedAd,
                RoundAd.none => sheetOpenedAt != null ? proto.RoundOverlay.hintSheet : proto.RoundOverlay.none,
              },
    overlaySeconds: sheetOpenedAt != null ? (sheetLeftMs / 1000).ceil() : 0,
  );
}
