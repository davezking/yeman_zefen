import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/theme/tokens.dart';
import '../features/game/domain/scorer.dart' as domain;
import '../features/game/domain/session_config.dart' as domain;
import 'mock_data.dart';
import 'models.dart';

/// A whole game played on a fake clock and a fake "playing" state, so the
/// pacing and the motion can be judged without audio or a server. It follows
/// the rules in `docs/scoring.md` (the real [domain.Scorer] counts the points)
/// and the timings in `docs/design/screens.md`:
///
/// - The clip plays for its length (10, 5 or 3 s); the answer window is the
///   clip plus 5 s. The timer stops under the hint sheet, the rewarded ad, the
///   leave dialog and while the app is in the background.
/// - A right answer shows for 1 s and moves on by itself. A wrong answer or a
///   time-out shows for 5 s, and a tap moves on sooner.
/// - A mandatory ad follows every 3rd round (the design's
///   `timing.interstitialEveryRounds`). Unlike the real game, which never shows
///   one in a first session, the prototype always does, so it can be judged.
///
/// Time moves in whole [MotionTokens.durationTimerTick] steps counted by the
/// simulation, not read from the clock, so tests can run a game with `pump`.
class RoundSimulation extends ChangeNotifier {
  RoundSimulation({
    required this.settings,
    this.totalRounds = 10,
    this.interstitialEvery = TimingTokens.interstitialEveryRounds,
    this.bestScore,
    Random? random,
    List<Track> catalog = mockTracks,
    this.clipLoadTime,
  }) : _random = random ?? Random() {
    _rounds = _buildRounds(catalog);
    _timer = Timer.periodic(MotionTokens.durationTimerTick, (_) => _tick());
    _startRound(0);
  }

  /// How long round [index]'s clip takes to arrive; null when it is already on
  /// the phone (nearly always). Longer than [TimingTokens.nextSongWaitMax]
  /// means it never arrives in time and the round is skipped.
  final Duration? Function(int index)? clipLoadTime;

  final PlaySettings settings;
  final int totalRounds;

  /// An ad after every this many rounds; 0 for none.
  final int interstitialEvery;

  /// The player's best before this game, to tell whether this one beat it.
  final int? bestScore;
  final Random _random;
  late final List<_RoundData> _rounds;
  late final Timer _timer;

  static final _tickMs = MotionTokens.durationTimerTick.inMilliseconds;
  static const _rewardedAdMs = 3000;
  static const _interstitialMs = 2500;

  final _scorer = const domain.Scorer();
  final _results = <RoundResult>[];

  int _round = 0;
  RoundPhase _phase = RoundPhase.answering;
  int _answerMs = 0;
  int _clipMs = 0;
  int _feedbackMs = 0;
  int? _picked;
  var _removed = <int>{};
  bool _hintUsed = false;
  int _points = 0;
  int _bonus = 0;
  int _score = 0;
  RoundOverlay _overlay = RoundOverlay.none;
  int _overlayMs = 0;
  bool _backgrounded = false;
  bool _finished = false;
  bool _left = false;
  bool _disposed = false;

  /// The game is over: show Results.
  bool get finished => _finished;

  /// The player confirmed "Leave".
  bool get left => _left;

  bool get backgrounded => _backgrounded;

  /// Rounds skipped because their clip did not arrive in time. Each one is
  /// worth a short notice; none costs points.
  int get skipped => _skipped;
  int _skipped = 0;
  int _loadMs = 0;
  int _loadNeededMs = 0;

  List<RoundResult> get results => List.unmodifiable(_results);
  int get score => _score;
  bool get newBest => _score > (bestScore ?? 0);

  domain.GameMode get _domainMode => switch (settings.mode) {
    GameMode.intro => domain.GameMode.intro,
    GameMode.middle => domain.GameMode.middle,
    GameMode.era => domain.GameMode.generation,
  };

  domain.Difficulty get _domainDifficulty => switch (settings.difficulty) {
    Difficulty.easy => domain.Difficulty.easy,
    Difficulty.medium => domain.Difficulty.medium,
    Difficulty.hard => domain.Difficulty.hard,
  };

  int get _clipLengthMs => settings.mode == GameMode.era
      ? domain.Scorer.generationClipMs
      : _domainDifficulty.clipLengthMs;

  int get _windowMs => _scorer.windowMs(_domainMode, _domainDifficulty);

  /// Which Era? asks for the era, so it never filters by one (the answer would
  /// always be the chosen era) and its chip reads "All eras".
  int get _eraFilter =>
      settings.mode == GameMode.era ? EraId.all : settings.generationId;

  bool get _timerStopped => _backgrounded || _overlay != RoundOverlay.none;

  /// What the round screen shows now.
  RoundView get view {
    final data = _rounds[_round];
    final leftMs = (_windowMs - _answerMs).clamp(0, _windowMs);
    final answering = _phase == RoundPhase.answering;
    return RoundView(
      roundNumber: _round + 1,
      totalRounds: totalRounds,
      score: _score,
      eraFilterId: _eraFilter,
      difficulty: settings.difficulty,
      kind: data.kind,
      options: data.options,
      correctIndex: data.correctIndex,
      track: data.track,
      phase: _phase,
      clipPlaying:
          answering &&
          _clipMs < _clipLengthMs &&
          !_backgrounded &&
          (_overlay == RoundOverlay.none || _overlay == RoundOverlay.hintSheet),
      timeFraction: leftMs / _windowMs,
      secondsLeft: (leftMs / 1000).ceil(),
      timerPaused: _timerStopped && answering,
      pickedIndex: _picked,
      removed: Set.unmodifiable(_removed),
      hintAvailable: answering && !_hintUsed,
      hintUsed: _hintUsed,
      points: _points,
      speedBonus: _bonus,
      feedbackSecondsLeft: (_feedbackMs / 1000).ceil(),
      overlay: _overlay,
      overlaySeconds: (_overlayMs / 1000).ceil(),
    );
  }

  // ---- what the player does ----

  /// Taps answer [index].
  void answer(int index) {
    if (_phase != RoundPhase.answering || _timerStopped) return;
    if (_removed.contains(index)) return;
    final data = _rounds[_round];
    final correct = index == data.correctIndex;
    final scored = _scorer.scoreRound(
      mode: _domainMode,
      difficulty: _domainDifficulty,
      correct: correct,
      responseMs: _answerMs,
      hintUsed: _hintUsed,
    );
    _picked = index;
    _points = scored.points;
    _bonus = scored.bonus;
    _score += scored.points;
    _phase = correct ? RoundPhase.correct : RoundPhase.wrong;
    _feedbackMs =
        (correct ? TimingTokens.feedbackCorrect : TimingTokens.feedbackWrong)
            .inMilliseconds;
    _results.add(
      RoundResult(
        track: data.track,
        correct: correct,
        points: scored.points,
        hintUsed: _hintUsed,
        number: _round + 1,
      ),
    );
    _changed();
  }

  /// Taps the hint button: the sheet opens and the timer stops.
  void requestHint() {
    if (_phase != RoundPhase.answering || _hintUsed) return;
    if (_overlay != RoundOverlay.none) return;
    _overlay = RoundOverlay.hintSheet;
    _overlayMs = TimingTokens.hintSheetMax.inMilliseconds;
    _changed();
  }

  /// "No thanks", or the sheet's 8 s ran out.
  void declineHint() {
    if (_overlay != RoundOverlay.hintSheet) return;
    _overlay = RoundOverlay.none;
    _changed();
  }

  /// "Watch ad": the fake rewarded ad plays, then two wrong answers go.
  void watchHintAd() {
    if (_overlay != RoundOverlay.hintSheet) return;
    _overlay = RoundOverlay.rewardedAd;
    _overlayMs = _rewardedAdMs;
    _changed();
  }

  /// A tap on the wrong-answer screen skips the rest of its 5 s.
  void tapContinue() {
    if (_phase == RoundPhase.answering || _overlay != RoundOverlay.none) return;
    if (_phase == RoundPhase.correct) return;
    _advance();
  }

  /// The app went to the background (true) or came back (false).
  void setBackgrounded(bool value) {
    if (_backgrounded == value) return;
    _backgrounded = value;
    _changed();
  }

  /// The back button: asks "Leave this game?" and stops the timer.
  void requestLeave() {
    if (_finished || _overlay == RoundOverlay.leaveDialog) return;
    _resumeAfterLeave = _overlay;
    _resumeAfterLeaveMs = _overlayMs;
    _overlay = RoundOverlay.leaveDialog;
    _changed();
  }

  RoundOverlay _resumeAfterLeave = RoundOverlay.none;
  int _resumeAfterLeaveMs = 0;

  /// "Keep playing".
  void cancelLeave() {
    if (_overlay != RoundOverlay.leaveDialog) return;
    _overlay = _resumeAfterLeave;
    _overlayMs = _resumeAfterLeaveMs;
    _changed();
  }

  /// "Leave": the game ends without a score.
  void confirmLeave() {
    if (_overlay != RoundOverlay.leaveDialog) return;
    _left = true;
    _timer.cancel();
    _changed();
  }

  // ---- the clock ----

  void _tick() {
    if (_disposed || _finished || _left || _backgrounded) return;
    switch (_overlay) {
      case RoundOverlay.leaveDialog:
      // The real engine's pause notice; the prototype pauses by being in the background.
      case RoundOverlay.paused:
        return;
      case RoundOverlay.hintSheet:
        _clipMs += _tickMs;
        _overlayMs -= _tickMs;
        if (_overlayMs <= 0) _overlay = RoundOverlay.none;
        _changed();
        return;
      case RoundOverlay.rewardedAd:
        _overlayMs -= _tickMs;
        if (_overlayMs <= 0) {
          _overlay = RoundOverlay.none;
          _hintUsed = true;
          _removed = _twoWrongAnswers();
        }
        _changed();
        return;
      case RoundOverlay.interstitial:
        _overlayMs -= _tickMs;
        if (_overlayMs <= 0) {
          _overlay = RoundOverlay.none;
          _startRound(_round + 1);
        }
        _changed();
        return;
      case RoundOverlay.none:
        break;
    }
    if (_phase == RoundPhase.loading) {
      _loadMs += _tickMs;
      if (_loadMs >= _loadNeededMs) {
        _phase = RoundPhase.answering;
      } else if (_loadMs >= TimingTokens.nextSongWaitMax.inMilliseconds) {
        // Waited long enough: skip the round, with no penalty.
        _skipped++;
        _advance();
        return;
      }
    } else if (_phase == RoundPhase.answering) {
      _answerMs += _tickMs;
      _clipMs += _tickMs;
      if (_answerMs >= _windowMs) {
        _answerMs = _windowMs;
        _phase = RoundPhase.timeout;
        _feedbackMs = TimingTokens.feedbackWrong.inMilliseconds;
        _results.add(
          RoundResult(
            track: _rounds[_round].track,
            correct: false,
            points: 0,
            hintUsed: _hintUsed,
            timedOut: true,
            number: _round + 1,
          ),
        );
      }
    } else {
      _feedbackMs -= _tickMs;
      if (_feedbackMs <= 0) {
        _advance();
        return;
      }
    }
    _changed();
  }

  void _advance() {
    final next = _round + 1;
    if (next >= totalRounds) {
      _finished = true;
      _timer.cancel();
    } else if (interstitialEvery > 0 && next % interstitialEvery == 0) {
      _overlay = RoundOverlay.interstitial;
      _overlayMs = _interstitialMs;
    } else {
      _startRound(next);
      return;
    }
    _changed();
  }

  void _startRound(int index) {
    _round = index;
    final load = clipLoadTime?.call(index);
    _loadMs = 0;
    _loadNeededMs = load?.inMilliseconds ?? 0;
    _phase = _loadNeededMs > 0 ? RoundPhase.loading : RoundPhase.answering;
    _answerMs = 0;
    _clipMs = 0;
    _feedbackMs = 0;
    _picked = null;
    _removed = <int>{};
    _hintUsed = false;
    _points = 0;
    _bonus = 0;
    _overlay = RoundOverlay.none;
    _changed();
  }

  Set<int> _twoWrongAnswers() {
    final wrong = [
      for (var i = 0; i < _rounds[_round].options.length; i++)
        if (i != _rounds[_round].correctIndex) i,
    ]..shuffle(_random);
    return wrong.take(2).toSet();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer.cancel();
    super.dispose();
  }

  // ---- the questions ----

  List<_RoundData> _buildRounds(List<Track> catalog) {
    var pool = [
      for (final t in catalog)
        if ((_eraFilter == EraId.all || t.generationId == _eraFilter) &&
            (settings.genre == Genre.any || t.genre == settings.genre))
          t,
    ];
    if (pool.isEmpty) pool = List.of(catalog);
    pool.shuffle(_random);

    final kinds = settings.mode == GameMode.era
        ? QuestionKind.era
        : (settings.guess == GuessTarget.artist
              ? QuestionKind.artist
              : QuestionKind.song);

    // The mock catalog is small (four songs an era), so a filtered game
    // repeats its songs; the real catalog has enough.
    return [
      for (var i = 0; i < totalRounds; i++)
        _buildRound(pool[i % pool.length], kinds, pool, catalog),
    ];
  }

  /// Wrong answers come from [pool] (the same era and genre) first, so they
  /// cannot be ruled out by era alone, then from the rest of [catalog].
  _RoundData _buildRound(
    Track track,
    QuestionKind kind,
    List<Track> pool,
    List<Track> catalog,
  ) {
    final List<RoundOption> options;
    if (kind == QuestionKind.era) {
      final eras = [
        for (final id in EraId.ordered)
          if (id != EraId.all && id != track.generationId) id,
      ]..shuffle(_random);
      options = [
        RoundOption.era(track.generationId),
        for (final id in eras.take(3)) RoundOption.era(id),
      ];
    } else {
      String key(Track t) =>
          kind == QuestionKind.artist ? t.artistLatin : t.titleLatin;
      final others = <Track>[];
      final seen = {key(track)};
      for (final t in [
        ...List.of(pool)..shuffle(_random),
        ...List.of(catalog)..shuffle(_random),
      ]) {
        if (seen.add(key(t))) others.add(t);
        if (others.length == 3) break;
      }
      options = [
        RoundOption.track(track),
        for (final t in others) RoundOption.track(t),
      ];
    }
    final shuffled = List.of(options)..shuffle(_random);
    final correctIndex = shuffled.indexWhere(
      (o) => identical(o, options.first),
    );
    return _RoundData(
      track: track,
      kind: kind,
      options: shuffled,
      correctIndex: correctIndex,
    );
  }
}

class _RoundData {
  const _RoundData({
    required this.track,
    required this.kind,
    required this.options,
    required this.correctIndex,
  });

  final Track track;
  final QuestionKind kind;
  final List<RoundOption> options;
  final int correctIndex;
}
