import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// The game's short sound effects, in `assets/sfx/`.
enum Sfx {
  correct('correct'),
  wrong('wrong'),
  timeout('timeout'),

  /// One per second over the last seconds of the answer window.
  tick('tick'),

  /// The session is over.
  gameOver('game_over');

  const Sfx(this.file);
  final String file;

  String get asset => 'assets/sfx/$file.wav';
}

/// Plays [Sfx]. Never throws: a sound that cannot play is skipped.
abstract class GameSfx {
  Future<void> play(Sfx sfx);

  void dispose();
}

/// No sound: tests, and anywhere audio plugins are missing.
class SilentGameSfx implements GameSfx {
  @override
  Future<void> play(Sfx sfx) async {}

  @override
  void dispose() {}
}

/// [GameSfx] on just_audio, one preloaded player per sound so a sound starts at once.
///
/// The players neither take audio focus nor react to interruptions: the round's clip owns the
/// audio session, and a sound effect over it must not look like another app taking audio.
class JustAudioGameSfx implements GameSfx {
  final _players = <Sfx, Future<AudioPlayer>>{};
  var _disposed = false;

  Future<AudioPlayer> _load(Sfx sfx) async {
    final player = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
    await player.setAsset(sfx.asset);
    return player;
  }

  /// Loads every sound ahead of the first one played.
  void preload() {
    for (final sfx in Sfx.values) {
      unawaited(_player(sfx).then((_) {}, onError: (Object _) {}));
    }
  }

  Future<AudioPlayer> _player(Sfx sfx) {
    final loading = _players[sfx] ??= _load(sfx);
    // A failed load is tried again next time.
    loading.then((_) {}, onError: (Object _) {
      _players.remove(sfx);
    });
    return loading;
  }

  @override
  Future<void> play(Sfx sfx) async {
    if (_disposed) return;
    try {
      final player = await _player(sfx);
      if (_disposed) return;
      await player.pause();
      await player.seek(Duration.zero);
      // Completes when the sound ends; nothing waits for that.
      unawaited(player.play().catchError((Object _) {}));
    } catch (e) {
      debugPrint('sfx: ${sfx.file} did not play: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final loading in _players.values) {
      unawaited(loading.then((p) => p.dispose(), onError: (Object _) {}));
    }
    _players.clear();
  }
}
