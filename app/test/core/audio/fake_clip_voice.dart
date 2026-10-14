import 'dart:async';

import 'package:yeman_zefen/core/audio/clip_voice.dart';

/// A [ClipVoice] with no audio engine. Tests drive position and completion.
class FakeClipVoice implements ClipVoice {
  Duration startDelay = const Duration(milliseconds: 20);
  Object? loadError;
  Object? startError;

  /// Runs when a start begins, before the start delay. Lets a test make time
  /// pass while the audio is still loading.
  void Function()? onStart;

  final loads = <(String, Duration)>[];

  /// Loads made while the voice was still playing. just_audio would start
  /// such a clip on its own, so this must stay 0.
  var loadsWhilePlaying = 0;
  var stops = 0;
  var playing = false;
  var disposed = false;

  Duration _position = Duration.zero;
  final _positions = StreamController<Duration>.broadcast();
  final _completed = StreamController<void>.broadcast();

  @override
  Future<void> load(String path, Duration limit) async {
    if (playing) loadsWhilePlaying++;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final error = loadError;
    if (error != null) throw error;
    loads.add((path, limit));
    _position = Duration.zero;
  }

  @override
  Future<void> start() async {
    onStart?.call();
    final error = startError;
    if (error != null) throw error;
    await Future<void>.delayed(startDelay);
    playing = true;
  }

  @override
  Future<void> stop() async {
    playing = false;
    stops++;
  }

  @override
  Stream<Duration> get position => _positions.stream;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Duration get currentPosition => _position;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  /// Moves the playback position, as the engine would while playing.
  void emitPosition(Duration p) {
    _position = p;
    _positions.add(p);
  }

  /// The clip reaches its limit. Like just_audio, the voice still counts as
  /// playing until it is paused.
  void finish() {
    if (loads.isNotEmpty) _position = loads.last.$2;
    _completed.add(null);
  }
}
