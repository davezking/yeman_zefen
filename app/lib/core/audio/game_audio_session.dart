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
Stream<void> gameAudioInterruptions() => interruptionsFrom(
      AudioSession.instance.then(
        (session) => (session.interruptionEventStream, session.becomingNoisyEventStream),
      ),
    );

/// The filtering behind [gameAudioInterruptions], over the session's two event
/// streams once they are available.
Stream<void> interruptionsFrom(
  Future<(Stream<AudioInterruptionEvent>, Stream<void>)> sources,
) {
  late final StreamController<void> controller;
  final subscriptions = <StreamSubscription<Object?>>[];
  var cancelled = false;

  controller = StreamController<void>(
    onListen: () async {
      final (interruptions, becomingNoisy) = await sources;
      // The listener may have gone while the session was loading.
      if (cancelled) return;
      subscriptions
        ..add(
          interruptions
              .where((e) => e.begin && e.type != AudioInterruptionType.duck)
              .listen((_) => controller.add(null)),
        )
        ..add(becomingNoisy.listen((_) => controller.add(null)));
    },
    onCancel: () async {
      cancelled = true;
      for (final s in subscriptions) {
        await s.cancel();
      }
      subscriptions.clear();
    },
  );
  return controller.stream;
}
