import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/clip_player.dart';
import '../../../core/audio/clip_voice.dart';
import '../../../core/db/app_db.dart';
import '../../../core/l10n/display_name.dart';
import '../../../core/net/network_kind.dart';
import '../../packs/data/clip_prefetcher.dart';
import '../../packs/data/clip_providers.dart';
import '../../packs/data/clip_settings.dart';
import '../../packs/data/clip_store.dart';
import '../../packs/data/packs_providers.dart';
import '../data/game_library.dart';
import '../data/session_store.dart';
import '../domain/generated_session.dart';
import '../domain/round_generator.dart';
import '../domain/scorer.dart';
import '../domain/session_config.dart';
import '../domain/session_payload.dart';
import 'session_environment.dart';
import 'session_state.dart';

final sessionEnvironmentProvider = Provider<SessionEnvironment>((ref) => SessionEnvironment.real());

final sessionStoreProvider = Provider<SessionStore>((ref) {
  final store = SessionStore(ref.watch(appDbProvider));
  ref.onDispose(store.dispose);
  return store;
});

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
  const _Interrupted(this.atMs);

  /// The monotonic time of the interruption.
  final int atMs;
}

class _Abandoned extends _Outcome {
  const _Abandoned();
}

/// How a round ended when it was not played to an answer: [clipError] says the clip file was
/// missing or would not play (counted as a clip error), otherwise no clip arrived in time and the
/// round was skipped without penalty.
class _RoundResult {
  const _RoundResult(this.summary, {this.clipError = false});
  final RoundSummary? summary;
  final bool clipError;
}

/// Runs a session: it picks the rounds, plays each clip, times the answer, scores
/// it, and at the end saves the session on the device.
///
/// A round's response time starts when [ClipPlayer.play] returns, which is when
/// audio is actually playing, not when the screen was built.
///
/// A round paused by a call or by the app going to the background plays its
/// clip again on resume, but the clock does not start over: the time used
/// before the pause still counts, and the window only has what was left. So
/// pausing gains a second listen and nothing else.
class SessionController extends Notifier<SessionState> {
  static const _scorer = Scorer();

  var _runId = 0;
  var _disposed = false;
  ClipPlayer? _player;
  ClipPrefetcher? _prefetcher;

  Completer<_Outcome>? _outcome;
  Completer<void>? _resume;
  Completer<void>? _feedbackWait;
  Timer? _windowTimer;
  Timer? _feedbackTimer;
  StreamSubscription<ClipStopInfo>? _interruptedSub;

  /// When the round's clock started, moved back by the time used before a
  /// pause, so `now - _roundStartedMs` is the whole response time.
  var _roundStartedMs = 0;

  /// The app is in the background. The next clip waits for Resume.
  var _backgrounded = false;

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
        _finishPrefetch();
        _set(SessionState(phase: SessionPhase.failed, config: config, error: SessionError(SessionProblem.unexpected, detail: '$e')));
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
  /// Between rounds, or while a clip loads, the next clip waits for Resume.
  void pauseForBackground() {
    if (state.phase != SessionPhase.preparing && state.phase != SessionPhase.playing) return;
    _backgrounded = true;
    unawaited(_stopPlayer());
    final pending = _outcome;
    if (pending != null && !pending.isCompleted) {
      pending.complete(_Interrupted(ref.read(sessionEnvironmentProvider).monotonicMs()));
    }
  }

  /// Plays the paused round's clip again. The answer window carries on from
  /// where it stopped.
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

  /// Lets running prefetches end, then trims the stream cache to its cap. Runs after every
  /// session, finished or left, and never delays the screen.
  void _finishPrefetch() {
    final prefetcher = _prefetcher;
    _prefetcher = null;
    if (prefetcher == null) return;
    ClipSettings? settings;
    try {
      settings = ref.read(clipSettingsProvider);
    } catch (_) {
      // The provider is being disposed: trim to the default cap.
    }
    unawaited(() async {
      var cap = ClipStore.defaultStreamCacheCapBytes;
      try {
        cap = await settings?.streamCacheCapBytes() ?? cap;
      } catch (_) {
        // Unreadable: trim to the default cap. The session must still end, or a pack removal
        // waiting for it would wait for ever.
      }
      try {
        await prefetcher.finish(capBytes: cap);
      } catch (_) {
        // The cache is trimmed after the next session instead.
      }
    }());
  }

  void _abandon() {
    _finishPrefetch();
    _runId++;
    _backgrounded = false;
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

    void fail(SessionError error) {
      unawaited(_stopPlayer());
      _set(SessionState(phase: SessionPhase.failed, config: config, error: error));
    }

    final base = await supportDirectory;
    check();
    try {
      // The bundled starter clips are registered before the catalog is read.
      await ref.read(starterReadyProvider.future);
    } catch (_) {}
    check();
    final library = await loadGameLibrary(db, base);
    check();
    if (library.isEmpty) {
      fail(const SessionError(SessionProblem.noSongs));
      return;
    }
    final recent = await store.recentTrackIds();
    check();

    // Clips can be fetched while playing when the phone is online and the player allows mobile
    // data (or is not on it). Otherwise only clips already on the device are asked about.
    final network = await _networkOf(env);
    final settings = ref.read(clipSettingsProvider);
    final allowDownloads = network == NetworkKind.unmetered ||
        (network == NetworkKind.cellular && await _prefetchOnMobile(settings));
    check();

    final generator = RoundGenerator(library.tracks, rng: env.rng());
    final GeneratedSession generated;
    try {
      generated = generator.generate(
        config,
        recentSessions: recent,
        playable: library.playableIds(config.mode, includeFetchable: allowDownloads),
      );
    } on RoundGenerationException catch (e) {
      fail(_explain(e, config));
      return;
    }

    final offlineAtStart = network == NetworkKind.none;
    final recorder = SessionRecorder(id: env.newId(), config: config, startedAtMs: env.epochMs());
    _interruptedSub = player.interrupted.listen((_) => _onInterrupted());

    final prefetcher = ClipPrefetcher(
      library: library,
      config: config,
      rounds: generated.rounds,
      generator: generator,
      downloader: ref.read(clipDownloaderProvider),
      store: ref.read(clipStoreProvider),
      fileExists: env.fileExists,
      timer: env.timer,
      allowDownloads: allowDownloads,
      rng: env.rng(),
      recentTrackIds: {for (final s in recent.take(RoundGenerator.historySessions)) ...s},
    );
    _prefetcher = prefetcher;

    final total = generated.rounds.length;
    final windowMs = _scorer.windowMs(config.mode, config.difficulty);
    final limitMs = config.difficulty.clipLengthMs;

    final played = <RoundSummary>[];
    var skipped = 0;
    for (var i = 0; i < total; i++) {
      prefetcher.prefetchFrom(i);
      final result = await _playRound(
        runId: runId,
        index: i,
        total: total,
        planned: prefetcher.roundAt(i),
        prepare: () => prefetcher.prepare(i),
        library: library,
        config: config,
        recorder: recorder,
        env: env,
        player: player,
        windowMs: windowMs,
        limitMs: limitMs,
        onPlaying: (trackId) => unawaited(prefetcher.markPlayed(trackId)),
        nextClip: () async {
          final path = prefetcher.readyPath(i + 1);
          return path != null && await env.fileExists(path) ? path : null;
        },
      );
      check();
      final summary = result.summary;
      if (summary == null) {
        // The clip is missing or will not play, or none arrived in time. The round is skipped.
        skipped++;
        if (result.clipError) await store.addClipError();
        check();
      } else {
        played.add(summary);
      }
    }

    final interrupted = _interruptedSub;
    _interruptedSub = null;
    await interrupted?.cancel();

    if (played.isEmpty) {
      _finishPrefetch();
      fail(SessionError(SessionProblem.clipsFailed, count: total));
      return;
    }

    final offlineAtEnd = await _networkOf(env) == NetworkKind.none;
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
    _finishPrefetch();

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

  /// Plays one round and returns how it went. The summary is null when its clip would not play
  /// (a clip error) or never arrived (skipped without penalty). Replays the round, with a fresh
  /// window, after an interruption.
  ///
  /// [prepare] makes the round's clip ready. It can hand back another round than [planned]: a
  /// swap for a track whose clip is on the device, with new options.
  Future<_RoundResult> _playRound({
    required int runId,
    required int index,
    required int total,
    required GeneratedRound planned,
    required Future<PreparedRound> Function() prepare,
    required GameLibrary library,
    required SessionConfig config,
    required SessionRecorder recorder,
    required SessionEnvironment env,
    required ClipPlayer player,
    required int windowMs,
    required int limitMs,
    required void Function(int trackId) onPlaying,
    required Future<String?> Function() nextClip,
  }) async {
    void check() {
      if (!_alive(runId)) throw const _Cancelled();
    }

    // Answer time used by earlier attempts of this round, before a pause.
    var usedMs = 0;

    var round = planned;
    var path = '';
    DisplayName nameOf(int id) => round.kind == QuestionKind.artist ? library.artistName(id) : library.trackName(id);
    var options = <AnswerOption>[];

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
        remainingMs: windowMs - usedMs,
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

    // The "next song loading" state: no options yet, because a swap may change them.
    show(view(RoundPhase.loading, 1));
    final prepared = await prepare();
    check();
    switch (prepared) {
      case RoundUnavailable(:final fileMissing):
        return _RoundResult(null, clipError: fileMissing);
      case RoundReady(round: final ready, path: final readyPath):
        round = ready;
        path = readyPath;
        options = [for (final id in round.optionIds) AnswerOption(id: id, name: nameOf(id))];
    }

    Future<void> waitForResume(int attempt) async {
      show(view(RoundPhase.interrupted, attempt));
      final resume = Completer<void>();
      _resume = resume;
      await resume.future;
      _resume = null;
      _backgrounded = false;
      check();
    }

    Future<_RoundResult> timedOut(int attempt) async {
      await _stopPlayer();
      check();
      recorder.recordRound(round, chosenId: null, responseMs: windowMs);
      usedMs = windowMs;
      show(view(RoundPhase.feedback, attempt, points: 0, timedOut: true));
      await _pause(env, env.feedbackDuration);
      check();
      return _RoundResult(RoundSummary(
        number: index + 1,
        kind: round.kind,
        correctName: nameOf(round.correctId),
        chosenName: null,
        correct: false,
        points: 0,
        valid: true,
        responseMs: windowMs,
      ));
    }

    var attempt = 0;
    while (true) {
      attempt++;
      show(view(RoundPhase.loading, attempt));
      try {
        await player.prepare(path, limitMs);
        check();
        if (_backgrounded) {
          // The app left the screen between rounds or while the clip loaded.
          // The clip stays loaded and starts when the player is back.
          await waitForResume(attempt);
          show(view(RoundPhase.loading, attempt));
        }
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
        return const _RoundResult(null, clipError: true);
      }

      // The clock starts here: the audio is playing. After a pause it carries on
      // from the time already used.
      _roundStartedMs = env.monotonicMs() - usedMs;
      onPlaying(round.trackId);
      unawaited(_preload(player, nextClip(), limitMs));

      final pending = Completer<_Outcome>();
      _outcome = pending;
      _windowTimer = env.timer(Duration(milliseconds: windowMs - usedMs), () {
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
        case _Interrupted(:final atMs):
          usedMs = atMs - _roundStartedMs;
          if (usedMs >= windowMs) return timedOut(attempt);
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
          return _RoundResult(RoundSummary(
            number: index + 1,
            kind: round.kind,
            correctName: nameOf(round.correctId),
            chosenName: nameOf(optionId),
            correct: correct,
            points: score.points,
            valid: score.valid,
            responseMs: responseMs,
          ));
        case _TimedOut():
          return timedOut(attempt);
      }
    }
  }

  void _onInterrupted() {
    final pending = _outcome;
    if (pending != null && !pending.isCompleted) {
      pending.complete(_Interrupted(ref.read(sessionEnvironmentProvider).monotonicMs()));
    }
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

  Future<NetworkKind> _networkOf(SessionEnvironment env) async {
    try {
      return await env.network();
    } catch (_) {
      return NetworkKind.unmetered;
    }
  }

  Future<bool> _prefetchOnMobile(ClipSettings settings) async {
    try {
      return await settings.prefetchOnMobile();
    } catch (_) {
      return true;
    }
  }

  SessionError _explain(RoundGenerationException e, SessionConfig config) {
    return switch (e.reason) {
      RoundGenerationReason.tooFewTracks => const SessionError(SessionProblem.tooFewSongs),
      RoundGenerationReason.tooFewArtists => const SessionError(SessionProblem.tooFewArtists),
      RoundGenerationReason.noTracksInEra =>
        SessionError(SessionProblem.noSongsInEra, generationId: config.generationId),
    };
  }
}
