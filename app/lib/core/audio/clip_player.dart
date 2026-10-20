import 'dart:async';

import '../crash/crash_reporting.dart';
import 'clip_voice.dart';

enum ClipStopReason {
  /// Playback reached the difficulty limit.
  limit,

  /// [ClipPlayer.stop] was called, for example when the player answered.
  stopped,

  /// A phone call, another app taking audio, or headphones unplugged.
  interrupted,
}

/// How a clip ended.
class ClipStopInfo {
  const ClipStopInfo({
    required this.reason,
    required this.positionMs,
    required this.playedMs,
  });

  final ClipStopReason reason;

  /// Where the player says it stopped, in clip time.
  final int positionMs;

  /// Wall-clock time from audio confirmed playing to the stop. For a clip that
  /// ends at its limit this should be very close to the limit.
  final int playedMs;
}

class ClipStartInfo {
  const ClipStartInfo({required this.latency});

  /// From the `play()` call until audio was confirmed playing.
  final Duration latency;
}

class _Clip {
  const _Clip(this.path, this.lengthMs);
  final String path;
  final int lengthMs;

  @override
  bool operator ==(Object other) =>
      other is _Clip && other.path == path && other.lengthMs == lengthMs;

  @override
  int get hashCode => Object.hash(path, lengthMs);
}

class _Slot {
  _Slot(this.voice);
  final ClipVoice voice;

  /// The clip loaded, or loading, in [voice]. Null when it holds nothing usable.
  _Clip? clip;
  Future<void>? loading;
}

/// Plays the short clips of a round.
///
/// Two players are used: one holds the current round's clip, the other
/// preloads the next round's. [prepare] swaps to the preloaded one, so a round
/// can start without waiting for a file to load. Two players were chosen over
/// one `ConcatenatingAudioSource` because the next clip is not known until the
/// round engine picks it, and a playlist would have to be edited while playing.
/// This has not been measured against the playlist on a device yet; the
/// results go in `docs/spikes/clip-playback.md`.
class ClipPlayer {
  /// [interruptions] fires when something takes audio away from the app. The
  /// clip is stopped, and [interrupted] reports it so the game can pause the round.
  ClipPlayer({
    required ClipVoice Function() voiceFactory,
    Stream<void> interruptions = const Stream.empty(),
  }) : _slots = [_Slot(voiceFactory()), _Slot(voiceFactory())] {
    _interruptionSub = interruptions.listen((_) => _onInterruption());
  }

  final List<_Slot> _slots;
  var _activeIndex = 0;
  late final StreamSubscription<void> _interruptionSub;

  final _elapsed = StreamController<int>.broadcast();
  final _completed = StreamController<ClipStopInfo>.broadcast();
  final _interrupted = StreamController<ClipStopInfo>.broadcast();

  var _playing = false;
  _Slot? _playingSlot;
  Stopwatch? _playStopwatch;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completedSub;

  _Slot get _active => _slots[_activeIndex];
  _Slot get _idle => _slots[1 - _activeIndex];

  /// Elapsed clip time in milliseconds while a clip plays.
  Stream<int> get elapsedMs => _elapsed.stream;

  /// A clip reached its limit.
  Stream<ClipStopInfo> get completed => _completed.stream;

  /// A clip was stopped by something outside the app.
  Stream<ClipStopInfo> get interrupted => _interrupted.stream;

  bool get isPlaying => _playing;

  /// Gets [path] ready to play, limited to its first [lengthMs]. Uses the
  /// clip loaded by [preloadNext] when it is the same one. Stops a clip that is
  /// still playing.
  Future<void> prepare(String path, int lengthMs) async {
    await stop();
    final clip = _Clip(path, lengthMs);

    final idle = _idle;
    if (idle.clip == clip) {
      try {
        await idle.loading;
        _active.clip = null; // the outgoing voice is free to preload again
        _activeIndex = 1 - _activeIndex;
        return;
      } catch (_) {
        // The preload failed. Load it directly below.
      }
    }
    await _load(_active, clip);
  }

  /// Loads the next round's clip while the current one plays.
  Future<void> preloadNext(String path, int lengthMs) =>
      _load(_idle, _Clip(path, lengthMs));

  Future<void> _load(_Slot slot, _Clip clip) async {
    slot.clip = clip;
    final loading = slot.voice.load(clip.path, Duration(milliseconds: clip.lengthMs));
    slot.loading = loading;
    try {
      await loading;
    } catch (_) {
      if (slot.clip == clip) slot.clip = null;
      rethrow;
    }
  }

  /// Starts the prepared clip. Completes once audio is actually playing.
  ///
  /// A clip plays once: after it stops, finishes or is interrupted, [prepare]
  /// it again. Throws [ClipStoppedException] when it is stopped before audio
  /// started, and [ClipPlaybackException] when it will not play.
  Future<ClipStartInfo> play() async {
    final slot = _active;
    if (slot.clip == null) {
      throw StateError('prepare() a clip before play()');
    }
    await stop();

    _playing = true;
    _playingSlot = slot;
    // Cleared so a stop before audio starts does not report the last clip's time.
    _playStopwatch = null;
    _positionSub = slot.voice.position.listen((p) => _elapsed.add(p.inMilliseconds));
    _completedSub = slot.voice.completed.listen((_) => _onCompleted(slot));

    final watch = Stopwatch()..start();
    try {
      await slot.voice.start();
    } catch (e, stack) {
      if (identical(_playingSlot, slot)) _detach();
      if (e is! ClipStoppedException) {
        recordNonFatal(e, stack, reason: 'audio_play_failed');
      }
      rethrow;
    }
    if (!identical(_playingSlot, slot)) {
      // stop() or an interruption arrived while starting. Make sure it is silent.
      await slot.voice.stop();
      throw const ClipStoppedException();
    }
    final latency = watch.elapsed;
    _playStopwatch = Stopwatch()..start();
    return ClipStartInfo(latency: latency);
  }

  /// Stops the clip at once. Returns how it ended, or null when nothing played.
  Future<ClipStopInfo?> stop() => _stopFor(ClipStopReason.stopped);

  Future<ClipStopInfo?> _stopFor(ClipStopReason reason) async {
    final slot = _playingSlot;
    if (!_playing || slot == null) return null;
    // Taken before the pause, so it measures when the stop was requested.
    final playedMs = _playStopwatch?.elapsedMilliseconds ?? 0;
    // The pause is requested in this same turn. Nothing is awaited before it.
    _detach();
    await slot.voice.stop();
    return ClipStopInfo(
      reason: reason,
      positionMs: slot.voice.currentPosition.inMilliseconds,
      playedMs: playedMs,
    );
  }

  void _onCompleted(_Slot slot) {
    if (!_playing || _playingSlot != slot) return;
    final info = ClipStopInfo(
      reason: ClipStopReason.limit,
      positionMs: slot.voice.currentPosition.inMilliseconds,
      playedMs: _playStopwatch?.elapsedMilliseconds ?? 0,
    );
    _detach();
    // A finished just_audio player still counts as playing, and would start the
    // next clip loaded into it on its own. Pause it.
    unawaited(slot.voice.stop().catchError((Object _) {}));
    if (!_completed.isClosed) _completed.add(info);
  }

  Future<void> _onInterruption() async {
    final info = await _stopFor(ClipStopReason.interrupted);
    if (info != null && !_interrupted.isClosed) _interrupted.add(info);
  }

  /// Marks nothing as playing and drops the voice listeners. Synchronous, so a
  /// caller can flip the state and act on the voice in the same turn.
  void _detach() {
    // The clip has been played. The voice has to load it again to replay it.
    _playingSlot?.clip = null;
    _playing = false;
    _playingSlot = null;
    final position = _positionSub;
    final completed = _completedSub;
    _positionSub = null;
    _completedSub = null;
    if (position != null) unawaited(position.cancel());
    if (completed != null) unawaited(completed.cancel());
  }

  Future<void> dispose() async {
    await _interruptionSub.cancel();
    _detach();
    await _elapsed.close();
    await _completed.close();
    await _interrupted.close();
    for (final slot in _slots) {
      await slot.voice.dispose();
    }
  }
}
