import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clip_player.dart';
import 'clip_voice.dart';
import 'game_audio_session.dart';

final clipPlayerProvider = Provider<ClipPlayer>((ref) {
  final player = ClipPlayer(
    voiceFactory: () => JustAudioClipVoice(),
    interruptions: gameAudioInterruptions(),
  );
  ref.onDispose(player.dispose);
  return player;
});
