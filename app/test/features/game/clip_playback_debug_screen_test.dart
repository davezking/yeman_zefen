import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/audio/audio_providers.dart';
import 'package:yeman_zefen/core/audio/clip_player.dart';
import 'package:yeman_zefen/features/game/debug/clip_playback_debug_screen.dart';

import '../../core/audio/fake_clip_voice.dart';

void main() {
  late List<FakeClipVoice> voices;
  late ClipPlayer player;

  setUp(() {
    voices = [];
    player = ClipPlayer(
      voiceFactory: () {
        final v = FakeClipVoice();
        voices.add(v);
        return v;
      },
    );
  });

  tearDown(() => player.dispose());

  Widget app({List<DebugTrack> tracks = const [DebugTrack(label: 'Song 1 · Artist', introPath: '/c/1-intro.mp3', middlePath: null)]}) {
    return ProviderScope(
      overrides: [
        clipPlayerProvider.overrideWithValue(player),
        debugClipTracksProvider.overrideWith((ref) async => tracks),
      ],
      child: const MaterialApp(home: ClipPlaybackDebugScreen()),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('says so when no tracks are installed', (tester) async {
    await tester.pumpWidget(app(tracks: const []));
    await settle(tester);
    expect(find.textContaining('No installed tracks'), findsOneWidget);
  });

  testWidgets('plays the chosen clip and shows the measured start latency', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Song 1 · Artist'), findsOneWidget);

    await tester.tap(find.text('5 s'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await settle(tester);

    // Preload is on by default, so the clip was loaded into the idle voice and swapped in.
    expect(voices[1].loads.single.$1, '/c/1-intro.mp3');
    expect(voices[1].loads.single.$2, const Duration(seconds: 5));
    expect(voices[1].playing, isTrue);
    expect(find.byKey(const Key('latency')), findsOneWidget);
    expect(find.byKey(const Key('prepare')), findsOneWidget);
  });

  testWidgets('without preload the clip loads into the active voice', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await settle(tester);

    expect(voices[0].loads, hasLength(1));
    expect(voices[1].loads, isEmpty);
    expect(voices[0].playing, isTrue);
  });

  testWidgets('shows where and when the clip stopped at its limit', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.text('Play'));
    await settle(tester);

    voices[1].finish();
    await settle(tester);

    expect(find.text('Stopped: limit'), findsOneWidget);
    expect(find.text('Position: 3000 ms'), findsOneWidget);
    expect(find.textContaining('vs 3000 ms'), findsOneWidget);
  });

  testWidgets('Stop ends the clip and reports it', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.text('Play'));
    await settle(tester);

    await tester.tap(find.text('Stop'));
    await settle(tester);

    expect(find.text('Stopped: stopped'), findsOneWidget);
    expect(player.isPlaying, isFalse);
  });

  testWidgets('reports a track that has no clip of the chosen type', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Middle'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await settle(tester);

    expect(find.text('This track has no middle clip'), findsOneWidget);
    expect(voices.every((v) => v.loads.isEmpty), isTrue);
  });
}
