import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/audio/game_audio_session.dart';

void main() {
  late StreamController<AudioInterruptionEvent> interruptions;
  late StreamController<void> noisy;

  setUp(() {
    interruptions = StreamController<AudioInterruptionEvent>.broadcast();
    noisy = StreamController<void>.broadcast();
  });

  tearDown(() async {
    await interruptions.close();
    await noisy.close();
  });

  Future<int> countEvents(void Function() fire) async {
    var count = 0;
    final sub = interruptionsFrom(Future.value((interruptions.stream, noisy.stream))).listen((_) => count++);
    await pumpEventQueue();
    fire();
    await pumpEventQueue();
    await sub.cancel();
    return count;
  }

  test('a call or another app taking audio stops the clip', () async {
    expect(await countEvents(() => interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause))), 1);
    expect(await countEvents(() => interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.unknown))), 1);
  });

  test('a notification that only ducks does not', () async {
    expect(await countEvents(() => interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck))), 0);
  });

  test('the end of an interruption does not', () async {
    expect(await countEvents(() => interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause))), 0);
  });

  test('headphones being unplugged does', () async {
    expect(await countEvents(() => noisy.add(null)), 1);
  });

  test('cancelling while the session loads leaves no listeners behind', () async {
    final sources = Completer<(Stream<AudioInterruptionEvent>, Stream<void>)>();
    final sub = interruptionsFrom(sources.future).listen((_) {});
    await sub.cancel();

    sources.complete((interruptions.stream, noisy.stream));
    await pumpEventQueue();

    expect(interruptions.hasListener, isFalse);
    expect(noisy.hasListener, isFalse);
  });

  test('cancelling after the session loaded removes the listeners', () async {
    final sub = interruptionsFrom(Future.value((interruptions.stream, noisy.stream))).listen((_) {});
    await pumpEventQueue();
    expect(interruptions.hasListener, isTrue);

    await sub.cancel();
    expect(interruptions.hasListener, isFalse);
    expect(noisy.hasListener, isFalse);
  });
}
