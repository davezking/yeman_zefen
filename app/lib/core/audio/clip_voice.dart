import 'dart:async';

import 'package:just_audio/just_audio.dart';

class ClipPlaybackException implements Exception {
  const ClipPlaybackException(this.message);
  final String message;

  @override
  String toString() => 'ClipPlaybackException: $message';
}

/// A clip was stopped, by a call or by leaving the screen, before its audio
/// started. Different from a clip that will not play at all.
class ClipStoppedException extends ClipPlaybackException {
  const ClipStoppedException() : super('stopped before audio started');
}

/// The clip decoded, but has less than [ClipTooShortException.minimum] of audio: a cut that went
/// wrong, not a clip to guess from.
class ClipTooShortException extends ClipPlaybackException {
  const ClipTooShortException(this.duration) : super('clip has under a second of audio');

  static const minimum = Duration(seconds: 1);

  final Duration duration;
}

/// One loaded audio slot: a single player that holds one clip at a time.
/// [ClipPlayer] keeps two of these so the next round's clip can load while the
/// current one plays. This is the seam that lets that logic be tested without
/// a platform audio engine.
abstract class ClipVoice {
  /// Loads [path] and limits playback to its first [limit]. Completes when the
  /// clip is ready to start without further loading. Throws
  /// [ClipTooShortException] when the clip has under a second of audio.
  Future<void> load(String path, Duration limit);

  /// Starts playback. Completes once audio is actually playing, not when the
  /// request was made. Throws if it does not start.
  Future<void> start();

  /// Stops playback at once. The loaded clip is kept, so a new [load] is needed
  /// before the next [start].
  Future<void> stop();

  /// Playback position, updated often enough to time reactions.
  Stream<Duration> get position;

  /// Fires when playback reaches the limit.
  Stream<void> get completed;

  Duration get currentPosition;

  Future<void> dispose();
}

/// [ClipVoice] backed by `just_audio`.
class JustAudioClipVoice implements ClipVoice {
  /// Interruptions are handled by [ClipPlayer], not by just_audio, which would
  /// otherwise resume a clip mid-way after a call and break response timing.
  JustAudioClipVoice({AudioPlayer? player})
      : _player = player ?? AudioPlayer(handleInterruptions: false);

  final AudioPlayer _player;

  static const _startTimeout = Duration(seconds: 5);

  @override
  Future<void> load(String path, Duration limit) async {
    // A player that is still "playing" (a finished clip counts as playing) would
    // start the new source as soon as it loads.
    await _player.pause();
    // The clip file already starts at the musical moment, so only the end is set.
    // The player enforces the end itself, so the stop is not a Dart timer.
    final duration = await _player.setAudioSource(
      ClippingAudioSource(
        child: AudioSource.file(path),
        start: Duration.zero,
        end: limit,
      ),
    );
    // The clipped length: the file's own when it is shorter than the limit. Unknown (null) is let
    // through, as a clip that will not play still fails when it starts.
    if (duration != null && duration < ClipTooShortException.minimum) throw ClipTooShortException(duration);
  }

  @override
  Future<void> start() async {
    // Listened to before play() so the first advance is not missed, and
    // cancelled however the start ends, so the fast poll does not outlive it.
    final started = Completer<void>();
    final positions = _player
        .createPositionStream(
          minPeriod: const Duration(milliseconds: 5),
          maxPeriod: const Duration(milliseconds: 20),
        )
        .listen((p) {
      if (!started.isCompleted &&
          p > Duration.zero &&
          _player.playing &&
          _player.processingState == ProcessingState.ready) {
        started.complete();
      }
    });
    try {
      // play() completes when playback ends, so it is not awaited. If it ends
      // before audio advanced, or fails, the start failed.
      final ended = _player.play().then<void>(
            (_) => throw const ClipPlaybackException('playback ended before audio started'),
          );
      await Future.any([started.future, ended]).timeout(
        _startTimeout,
        onTimeout: () => throw const ClipPlaybackException('audio did not start in time'),
      );
    } finally {
      await positions.cancel();
    }
  }

  @override
  Future<void> stop() => _player.pause();

  @override
  Stream<Duration> get position => _player.createPositionStream(
        minPeriod: const Duration(milliseconds: 20),
        maxPeriod: const Duration(milliseconds: 50),
      );

  @override
  Stream<void> get completed => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  @override
  Duration get currentPosition => _player.position;

  @override
  Future<void> dispose() => _player.dispose();
}
