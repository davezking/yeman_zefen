import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'clip_player.dart';
import 'clip_voice.dart';
import 'game_audio_session.dart';
import 'game_sfx.dart';

final clipPlayerProvider = Provider<ClipPlayer>((ref) {
  final player = ClipPlayer(
    voiceFactory: () => JustAudioClipVoice(),
    interruptions: gameAudioInterruptions(),
  );
  ref.onDispose(player.dispose);
  return player;
});

/// The sound effects. Silent in tests, which are built without a flavor and have no audio plugins.
final gameSfxProvider = Provider<GameSfx>((ref) {
  if (AppConfig.flavor.isEmpty) return SilentGameSfx();
  final sfx = JustAudioGameSfx()..preload();
  ref.onDispose(sfx.dispose);
  return sfx;
});
