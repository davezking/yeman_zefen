import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/audio/clip_player.dart';
import 'package:yeman_zefen/core/audio/clip_voice.dart';

import 'fake_clip_voice.dart';

void main() {
  late List<FakeClipVoice> voices;
  late StreamController<void> interruptions;
  late ClipPlayer player;

  setUp(() {
    voices = [];
    interruptions = StreamController<void>.broadcast();
    player = ClipPlayer(
      voiceFactory: () {
        final v = FakeClipVoice();
        voices.add(v);
        return v;
      },
      interruptions: interruptions.stream,
    );
  });

  tearDown(() async {
    await player.dispose();
    await interruptions.close();
  });

  group('prepare and play', () {
    test('prepare loads the clip limited to the requested length', () async {
      await player.prepare('a.mp3', 3000);
      expect(voices[0].loads, [('a.mp3', const Duration(seconds: 3))]);
    });

    test('play completes once audio has started and reports the latency', () async {
      await player.prepare('a.mp3', 3000);
      voices[0].startDelay = const Duration(milliseconds: 30);

      final start = await player.play();

      expect(voices[0].playing, isTrue);
      expect(player.isPlaying, isTrue);
      expect(start.latency, greaterThanOrEqualTo(const Duration(milliseconds: 30)));
    });

    test('play without prepare throws', () async {
      await expectLater(player.play(), throwsStateError);
    });

    test('a start failure is rethrown and nothing is left playing', () async {
      await player.prepare('a.mp3', 3000);
      voices[0].startError = const ClipPlaybackException('no audio');

      await expectLater(player.play(), throwsA(isA<ClipPlaybackException>()));
      expect(player.isPlaying, isFalse);
    });

    test('preparing the next clip stops one that is still playing', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();

      await player.prepare('b.mp3', 3000);

      expect(player.isPlaying, isFalse);
      expect(voices[0].playing, isFalse);
    });
  });

  group('preload', () {
    test('loads the next clip into the other voice while one plays', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();

      await player.preloadNext('b.mp3', 5000);

      expect(voices[1].loads, [('b.mp3', const Duration(seconds: 5))]);
      expect(voices[0].playing, isTrue);
    });

    test('prepare uses a preloaded clip without loading it again', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();
      await player.preloadNext('b.mp3', 3000);

      await player.prepare('b.mp3', 3000);
      await player.play();

      expect(voices[0].loads, hasLength(1));
      expect(voices[1].loads, hasLength(1));
      expect(voices[1].playing, isTrue);
      expect(voices[0].playing, isFalse);
    });

    test('a different clip than the preloaded one loads into the active voice', () async {
      await player.preloadNext('b.mp3', 3000);

      await player.prepare('c.mp3', 3000);

      expect(voices[0].loads, [('c.mp3', const Duration(seconds: 3))]);
      expect(voices[1].loads, [('b.mp3', const Duration(seconds: 3))]);
    });

    test('the same file with another limit is not a match', () async {
      await player.preloadNext('b.mp3', 3000);

      await player.prepare('b.mp3', 5000);

      expect(voices[0].loads, [('b.mp3', const Duration(seconds: 5))]);
    });

    test('prepare waits for a preload of the same clip that is still loading', () async {
      final preload = player.preloadNext('b.mp3', 3000);

      await player.prepare('b.mp3', 3000);
      await preload;

      expect(voices[0].loads, isEmpty);
      expect(voices[1].loads, hasLength(1));
      await player.play();
      expect(voices[1].playing, isTrue);
    });

    test('a failed preload is reported and prepare loads the clip itself', () async {
      voices[1].loadError = const ClipPlaybackException('bad file');

      await expectLater(player.preloadNext('b.mp3', 3000), throwsA(isA<ClipPlaybackException>()));
      voices[1].loadError = null;
      await player.prepare('b.mp3', 3000);

      expect(voices[0].loads, [('b.mp3', const Duration(seconds: 3))]);
    });
  });

  group('while playing', () {
    test('elapsedMs follows the playback position', () async {
      await player.prepare('a.mp3', 3000);
      final seen = player.elapsedMs.take(2).toList();
      await player.play();

      voices[0].emitPosition(const Duration(milliseconds: 100));
      voices[0].emitPosition(const Duration(milliseconds: 200));

      expect(await seen, [100, 200]);
    });

    test('reaching the limit reports completed and stops playing', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();
      final done = player.completed.first;

      voices[0].finish();
      final info = await done;

      expect(info.reason, ClipStopReason.limit);
      expect(info.positionMs, 3000);
      expect(player.isPlaying, isFalse);
    });

    test('stop returns how the clip ended', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();
      voices[0].emitPosition(const Duration(milliseconds: 1200));

      final info = await player.stop();

      expect(info, isNotNull);
      expect(info!.reason, ClipStopReason.stopped);
      expect(info.positionMs, 1200);
      expect(voices[0].playing, isFalse);
      expect(player.isPlaying, isFalse);
    });

    test('a clip that was stopped does not report completed afterwards', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();
      var fired = false;
      player.completed.listen((_) => fired = true);

      await player.stop();
      voices[0].finish();
      await pumpEventQueue();

      expect(fired, isFalse);
    });

    test('stop asks the voice to pause in the same turn', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();

      final pending = player.stop();
      // Nothing was awaited yet: the pause has already been requested.
      expect(voices[0].playing, isFalse);
      await pending;
    });

    test('stop with nothing playing returns null', () async {
      expect(await player.stop(), isNull);
    });
  });

  group('interruptions', () {
    test('stop the clip and report it', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();
      voices[0].emitPosition(const Duration(milliseconds: 800));
      final reported = player.interrupted.first;

      interruptions.add(null);
      final info = await reported;

      expect(info.reason, ClipStopReason.interrupted);
      expect(info.positionMs, 800);
      expect(voices[0].playing, isFalse);
      expect(player.isPlaying, isFalse);
    });

    test('are ignored when nothing is playing', () async {
      await player.prepare('a.mp3', 3000);
      var fired = false;
      player.interrupted.listen((_) => fired = true);

      interruptions.add(null);
      await pumpEventQueue();

      expect(fired, isFalse);
      expect(voices[0].stops, 0);
    });

    test('leave the player usable for the next clip', () async {
      await player.prepare('a.mp3', 3000);
      await player.play();
      interruptions.add(null);
      await pumpEventQueue();

      await player.prepare('b.mp3', 3000);
      await player.play();

      expect(player.isPlaying, isTrue);
    });
  });

  test('dispose releases both voices', () async {
    await player.dispose();
    expect(voices.every((v) => v.disposed), isTrue);
    expect(voices, hasLength(2));
    // tearDown disposes again; the player must tolerate that.
  });
}
