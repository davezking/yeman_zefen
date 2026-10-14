import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/clip_player.dart';
import '../../../core/audio/clip_voice.dart';
import '../../../core/db/app_db.dart';
import '../../packs/data/packs_providers.dart';
import '../data/game_library.dart';
import '../data/session_store.dart';
import '../domain/eras.dart';
import '../domain/generated_session.dart';
import '../domain/round_generator.dart';
import '../domain/scorer.dart';
import '../domain/session_config.dart';
import '../domain/session_payload.dart';
import 'session_environment.dart';
import 'session_state.dart';

final sessionEnvironmentProvider = Provider<SessionEnvironment>((ref) => SessionEnvironment.real());

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore(ref.watch(appDbProvider)));

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// The best score for a mode and era, for the start screen.
final bestScoreProvider = FutureProvider.autoDispose.family<int?, (GameMode, int)>((ref, key) {
  return ref.watch(sessionStoreProvider).bestScore(key.$1, key.$2);
});

class _Cancelled implements Exception {
  const _Cancelled();
}

sealed class _Outcome {
  const _Outcome();
}

class _Answered extends _Outcome {
  const _Answered(this.optionId, this.responseMs);
  final int optionId;
  final int responseMs;
}

class _TimedOut extends _Outcome {
  const _TimedOut();
}

class _Interrupted extends _Outcome {
  const _Interrupted();
}

class _Abandoned extends _Outcome {
  const _Abandoned();
}

/// Runs a session: it picks the rounds, plays each clip, times the answer, scores
/// it, and at the end saves the session on the device.
///
/// A round's response time starts when [ClipPlayer.play] returns, which is when
/// audio is actually playing, not when the screen was built.
class SessionController extends Notifier<SessionState> {
  static const _scorer = Scorer();

  var _runId = 0;
  var _disposed = false;
  ClipPlayer? _player;

  Completer<_Outcome>? _outcome;
  Completer<void>? _resume;
  Completer<void>? _feedbackWait;
  Timer? _windowTimer;
  Timer? _feedbackTimer;
  StreamSubscription<ClipStopInfo>? _interruptedSub;
  var _roundStartedMs = 0;

  @override
  SessionState build() {
    ref.onDispose(() {
      _disposed = true;
      _abandon();
    });
    return SessionState.idle;
  }

  /// Starts a session. A session already running is dropped first.
  Future<void> start(SessionConfig config) async {
    _abandon();
    final runId = _runId;
    final env = ref.read(sessionEnvironmentProvider);
    final store = ref.read(sessionStoreProvider);
    final db = ref.read(appDbProvider);
    final player = ref.read(clipPlayerProvider);
    final supportDirectory = ref.read(supportDirectoryProvider.future);
    _player = player;

    _set(SessionState(phase: SessionPhase.preparing, config: config));
    try {
      await _run(runId, config, env, store, db, player, supportDirectory);
    } on _Cancelled {
      // The player left the session.
    } catch (e) {
      if (_alive(runId)) {
        unawaited(_stopPlayer());
        _set(SessionState(phase: SessionPhase.failed, config: config, error: 'Something went wrong: $e'));
      }
    }
  }

  /// The player tapped an option. The audio stops at once and the response time
  /// is taken in this same call.
  void answer(int optionId) {
    final pending = _outcome;
    final round = state.round;
    if (pending == null || pending.isCompleted || round == null || round.phase != RoundPhase.answering) return;
    if (!round.options.any((o) => o.id == optionId)) return;
    final responseMs = ref.read(sessionEnvironmentProvider).monotonicMs() - _roundStartedMs;
    unawaited(_stopPlayer());
    pending.complete(_Answered(optionId, responseMs));
  }

  /// The app went to the background. The round pauses as it does after a call,
  /// so a clip does not keep playing, and the window does not run out, unseen.
  void pauseForBackground() {
    final pending = _outcome;
    if (pending == null || pending.isCompleted) return;
    unawaited(_stopPlayer());
    pending.complete(const _Interrupted());
  }

  /// Plays the interrupted round again, with a fresh answer window.
  void resume() {
    final pending = _resume;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Leaves the session without saving it.
  void leave() {
    _abandon();
    _set(SessionState.idle);
  }

  bool _alive(int runId) => !_disposed && runId == _runId;

  void _set(SessionState next) {
    if (!_disposed) state = next;
  }

  Future<void> _stopPlayer() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void _abandon() {
    _runId++;
    _windowTimer?.cancel();
    _windowTimer = null;
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    final outcome = _outcome;
    _outcome = null;
    if (outcome != null && !outcome.isCompleted) outcome.complete(const _Abandoned());
    final resume = _resume;
    _resume = null;
    if (resume != null && !resume.isCompleted) resume.complete();
    final feedback = _feedbackWait;
    _feedbackWait = null;
    if (feedback != null && !feedback.isCompleted) feedback.complete();
    final interrupted = _interruptedSub;
    _interruptedSub = null;
    if (interrupted != null) unawaited(interrupted.cancel());
    unawaited(_stopPlayer());
  }

  Future<void> _run(
    int runId,
    SessionConfig config,
    SessionEnvironment env,
    SessionStore store,
    AppDb db,
    ClipPlayer player,
    Future<dynamic> supportDirectory,
  ) async {
    void check() {
      if (!_alive(runId)) throw const _Cancelled();
    }

    void fail(String message) {
      unawaited(_stopPlayer());
      _set(SessionState(phase: SessionPhase.failed, config: config, error: message));
    }

    final base = await supportDirectory;
    check();
    final library = await loadGameLibrary(db, base);
    check();
    if (library.isEmpty) {
      fail('No songs are installed yet. Install a pack first.');
      return;
    }
    final recent = await store.recentTrackIds();
    check();

    final GeneratedSession generated;
    try {
      generated = RoundGenerator(library.tracks, rng: env.rng()).generate(config, recentSessions: recent);
    } on RoundGenerationException catch (e) {
      fail(_explain(e, config));
      return;
    }

    final offlineAtStart = await _isOffline(env);
    check();
    final recorder = SessionRecorder(id: env.newId(), config: config, startedAtMs: env.epochMs());
    _interruptedSub = player.interrupted.listen((_) => _onInterrupted());

    final total = generated.rounds.length;
    final windowMs = _scorer.windowMs(config.mode, config.difficulty);
    final limitMs = config.difficulty.clipLengthMs;

    Future<String?> clipOf(int index) async {
      if (index >= total) return null;
      final path = library.clipPath(generated.rounds[index].trackId, config.mode);
      return path != null && await env.fileExists(path) ? path : null;
    }

    final played = <RoundSummary>[];
    var skipped = 0;
    for (var i = 0; i < total; i++) {
      final path = await clipOf(i);
      check();
      RoundSummary? summary;
      if (path != null) {
        summary = await _playRound(
          runId: runId,
          index: i,
          total: total,
          round: generated.rounds[i],
          path: path,
          library: library,
          config: config,
          recorder: recorder,
          env: env,
          player: player,
          windowMs: windowMs,
          limitMs: limitMs,
          nextClip: () => clipOf(i + 1),
        );
      }
      check();
      if (summary == null) {
        // The clip is missing or will not play. The round is skipped.
        skipped++;
        await store.addClipError();
        check();
      } else {
        played.add(summary);
      }
    }

    final interrupted = _interruptedSub;
    _interruptedSub = null;
    await interrupted?.cancel();

    if (played.isEmpty) {
      fail('None of the $total clips could be played. Reinstall the pack and try again.');
      return;
    }

    final offlineAtEnd = await _isOffline(env);
    check();
    final payload = recorder.finish(endedAtMs: env.epochMs(), offline: offlineAtStart || offlineAtEnd);
    final totalScore = played.fold<int>(0, (sum, r) => sum + r.points);

    SessionSaveResult? saved;
    String? saveError;
    try {
      saved = await store.saveCompleted(payload: payload, score: totalScore, nowMs: env.epochMs());
    } catch (e) {
      saveError = '$e';
    }
    check();

    _set(
      SessionState(
        phase: SessionPhase.finished,
        config: config,
        summary: SessionSummary(
          config: config,
          totalScore: totalScore,
          rounds: played,
          skipped: skipped,
          flagged: played.any((r) => !r.valid),
          bestBefore: saved?.previousBest,
          isNewBest: saved?.isNewBest ?? false,
          saveError: saveError,
        ),
      ),
    );
  }

  /// Plays one round and returns how it went, or null when its clip would not
  /// play. Replays the round, with a fresh window, after an interruption.
  Future<RoundSummary?> _playRound({
    required int runId,
    required int index,
    required int total,
    required GeneratedRound round,
    required String path,
    required GameLibrary library,
    required SessionConfig config,
    required SessionRecorder recorder,
    required SessionEnvironment env,
    required ClipPlayer player,
    required int windowMs,
    required int limitMs,
    required Future<String?> Function() nextClip,
  }) async {
    void check() {
      if (!_alive(runId)) throw const _Cancelled();
    }

    String labelOf(int id) => round.kind == QuestionKind.artist ? library.artistLabel(id) : library.trackLabel(id);
    final options = [for (final id in round.optionIds) AnswerOption(id: id, label: labelOf(id))];

    RoundView view(
      RoundPhase phase,
      int attempt, {
      int? chosenId,
      int? points,
      bool timedOut = false,
      bool valid = true,
    }) {
      return RoundView(
        number: index + 1,
        total: total,
        kind: round.kind,
        options: options,
        windowMs: windowMs,
        phase: phase,
        attempt: attempt,
        chosenId: chosenId,
        correctId: phase == RoundPhase.feedback ? round.correctId : null,
        points: points,
        timedOut: timedOut,
        valid: valid,
      );
    }

    void show(RoundView v) => _set(SessionState(phase: SessionPhase.playing, config: config, round: v));

    Future<void> waitForResume(int attempt) async {
      show(view(RoundPhase.interrupted, attempt));
      final resume = Completer<void>();
      _resume = resume;
      await resume.future;
      _resume = null;
      check();
    }

    var attempt = 0;
    while (true) {
      attempt++;
      show(view(RoundPhase.loading, attempt));
      try {
        await player.prepare(path, limitMs);
        check();
        await player.play();
        check();
      } on ClipStoppedException {
        // A call or another app took the audio before it started.
        check();
        await waitForResume(attempt);
        continue;
      } catch (e) {
        if (e is _Cancelled) rethrow;
        check();
        return null;
      }

      // The clock starts here: the audio is playing.
      _roundStartedMs = env.monotonicMs();
      unawaited(_preload(player, nextClip(), limitMs));

      final pending = Completer<_Outcome>();
      _outcome = pending;
      _windowTimer = env.timer(Duration(milliseconds: windowMs), () {
        if (!pending.isCompleted) pending.complete(const _TimedOut());
      });
      show(view(RoundPhase.answering, attempt));

      final outcome = await pending.future;
      _windowTimer?.cancel();
      _windowTimer = null;
      _outcome = null;
      check();

      switch (outcome) {
        case _Abandoned():
          throw const _Cancelled();
        case _Interrupted():
          await waitForResume(attempt);
          continue;
        case _Answered(:final optionId, :final responseMs):
          final correct = round.isCorrect(optionId);
          final score = _scorer.scoreRound(
            mode: config.mode,
            difficulty: config.difficulty,
            correct: correct,
            responseMs: responseMs,
          );
          recorder.recordRound(round, chosenId: optionId, responseMs: responseMs);
          show(view(RoundPhase.feedback, attempt, chosenId: optionId, points: score.points, valid: score.valid));
          await _pause(env, env.feedbackDuration);
          check();
          return RoundSummary(
            number: index + 1,
            kind: round.kind,
            correctLabel: labelOf(round.correctId),
            chosenLabel: labelOf(optionId),
            correct: correct,
            points: score.points,
            valid: score.valid,
            responseMs: responseMs,
          );
        case _TimedOut():
          await _stopPlayer();
          check();
          recorder.recordRound(round, chosenId: null, responseMs: windowMs);
          show(view(RoundPhase.feedback, attempt, points: 0, timedOut: true));
          await _pause(env, env.feedbackDuration);
          check();
          return RoundSummary(
            number: index + 1,
            kind: round.kind,
            correctLabel: labelOf(round.correctId),
            chosenLabel: null,
            correct: false,
            points: 0,
            valid: true,
            responseMs: windowMs,
          );
      }
    }
  }

  void _onInterrupted() {
    final pending = _outcome;
    if (pending != null && !pending.isCompleted) pending.complete(const _Interrupted());
  }

  /// Loads the next round's clip while this one plays. A failure only means the
  /// next round loads when it starts.
  Future<void> _preload(ClipPlayer player, Future<String?> next, int limitMs) async {
    try {
      final path = await next;
      if (path != null) await player.preloadNext(path, limitMs);
    } catch (_) {}
  }

  Future<void> _pause(SessionEnvironment env, Duration duration) async {
    final done = Completer<void>();
    _feedbackWait = done;
    _feedbackTimer = env.timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    _feedbackWait = null;
    _feedbackTimer = null;
  }

  Future<bool> _isOffline(SessionEnvironment env) async {
    try {
      return await env.isOffline();
    } catch (_) {
      return false;
    }
  }

  String _explain(RoundGenerationException e, SessionConfig config) {
    return switch (e.reason) {
      RoundGenerationReason.tooFewTracks => 'Not enough songs are installed to make a round. Install another pack.',
      RoundGenerationReason.tooFewArtists =>
        'Not enough different artists for artist questions. Choose Song or Mixed, or install another pack.',
      RoundGenerationReason.noTracksInEra => 'No songs are installed for ${eraName(config.generationId)}. Choose another era.',
    };
  }
}
