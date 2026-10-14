import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// Configures the app's audio session for short game clips. Call once at startup.
///
/// Other apps' audio is ducked while a clip plays and restored afterwards:
/// Android asks for transient focus, and iOS ducks others and notifies them when
/// the session deactivates. The app never takes audio away permanently.
Future<void> configureGameAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.game,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ),
  );
}

/// Events that should stop a playing clip: a call or another app taking audio
/// (a short ducking by a notification is not one, the system lowers the volume
/// and the clip keeps going), and headphones being unplugged.
Stream<void> gameAudioInterruptions() {
  late final StreamController<void> controller;
  final subscriptions = <StreamSubscription<void>>[];

  controller = StreamController<void>(
    onListen: () async {
      final session = await AudioSession.instance;
      if (controller.isClosed) return;
      subscriptions.add(
        session.interruptionEventStream
            .where((e) => e.begin && e.type != AudioInterruptionType.duck)
            .listen((_) => controller.add(null)),
      );
      subscriptions.add(
        session.becomingNoisyEventStream.listen((_) => controller.add(null)),
      );
    },
    onCancel: () async {
      for (final s in subscriptions) {
        await s.cancel();
      }
      subscriptions.clear();
    },
  );
  return controller.stream;
}
