import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/domain/game_track.dart';
import 'package:yeman_zefen/features/game/domain/generated_session.dart';
import 'package:yeman_zefen/features/game/domain/round_generator.dart';
import 'package:yeman_zefen/features/game/domain/scorer.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/game/domain/session_payload.dart';

import 'doc_files.dart';

/// The JSON blocks in docs/session-payload.md: [0] is the shape, [1] the example.
List<Map<String, dynamic>> _docBlocks() {
  final blocks = RegExp(r'```json\n(.*?)\n```', dotAll: true).allMatches(readDoc('session-payload.md'));
  return [for (final m in blocks) jsonDecode(m.group(1)!) as Map<String, dynamic>];
}

/// The JSON type of a value, so a `_Map<String, Object?>` and a decoded map compare equal.
String _kind(Object? v) => switch (v) {
      null => 'null',
      String() => 'string',
      int() => 'int',
      bool() => 'bool',
      List() => 'list',
      Map() => 'map',
      _ => v.runtimeType.toString(),
    };

void main() {
  final tracks = [
    for (var i = 1; i <= 30; i++) GameTrack(id: i, artistId: 100 + i % 8, generationId: 1 + i % 2),
  ];

  late GeneratedSession session;
  late SessionRecorder recorder;

  setUp(() {
    final config = const SessionConfig(mode: GameMode.middle, difficulty: Difficulty.hard, generationId: 2);
    session = RoundGenerator(tracks, rng: Random(7)).generate(config);
    recorder = SessionRecorder(id: '6f0d2c1e-4b7a-4c52-9d0e-1a2b3c4d5e6f', config: config, startedAtMs: 1760000000000);
  });

  /// Answers every round correctly, 3 s after the audio started.
  void playAllCorrectly() {
    for (final r in session.rounds) {
      recorder.recordRound(r, chosenId: r.correctId, responseMs: 3000);
    }
  }

  group('payload shape', () {
    test('has the keys of the shape in docs/session-payload.md', () {
      playAllCorrectly();
      final json = recorder.finish(endedAtMs: 1760000095000, offline: true).toJson();
      final shape = _docBlocks()[0];

      expect(json.keys.toList(), shape.keys.toList());
      expect((json['rounds'] as List).first.keys.toList(), (shape['rounds'] as List).first.keys.toList());
      expect((json['ads'] as Map).keys.toList(), (shape['ads'] as Map).keys.toList());
    });

    test('has the keys and value types of the example in docs/session-payload.md', () {
      playAllCorrectly();
      final json = recorder.finish(endedAtMs: 1760000095000, offline: true).toJson();
      final example = _docBlocks()[1];

      expect(json.keys.toList(), example.keys.toList());
      for (final key in example.keys) {
        expect(_kind(json[key]), _kind(example[key]), reason: key);
      }
      final exampleRound = (example['rounds'] as List).first as Map<String, dynamic>;
      final round = (json['rounds'] as List).first as Map<String, Object?>;
      expect(round.keys.toList(), exampleRound.keys.toList());
      expect(round['optionIds'], isA<List<int>>());
      expect(exampleRound['optionIds'], hasLength(4));
    });

    test('survives a JSON round trip unchanged', () {
      playAllCorrectly();
      final json = recorder.finish(endedAtMs: 1760000095000, offline: false).toJson();
      expect(jsonDecode(jsonEncode(json)), json);
    });

    test('is a map of plain JSON types', () {
      playAllCorrectly();
      final json = recorder.finish(endedAtMs: 1760000095000, offline: true).toJson();
      expect(() => jsonEncode(json), returnsNormally);
    });
  });

  group('payload values', () {
    test('carry the session settings', () {
      playAllCorrectly();
      final json = recorder.finish(endedAtMs: 1760000095000, offline: true).toJson();
      expect(json['id'], '6f0d2c1e-4b7a-4c52-9d0e-1a2b3c4d5e6f');
      expect(json['mode'], 'middle');
      expect(json['generationId'], 2);
      expect(json['difficulty'], 'hard');
      expect(json['clientStartedAt'], 1760000000000);
      expect(json['clientEndedAt'], 1760000095000);
      expect(json['offline'], isTrue);
    });

    test('carry the ad counts', () {
      final json = recorder.finish(endedAtMs: 1, offline: false, interstitialShown: 2, rewardedCompleted: 1).toJson();
      expect(json['ads'], {'interstitialShown': 2, 'rewardedCompleted': 1});
      expect(json['offline'], isFalse);
    });

    test('record each round in the order it was played', () {
      playAllCorrectly();
      final rounds = recorder.finish(endedAtMs: 1, offline: true).toJson()['rounds']! as List;
      expect(rounds, hasLength(session.rounds.length));
      for (var i = 0; i < rounds.length; i++) {
        final r = session.rounds[i];
        expect(rounds[i], {
          'trackId': r.trackId,
          'question': r.kind.name,
          'optionIds': r.optionIds,
          'chosenId': r.correctId,
          'responseMs': 3000,
          'hintUsed': false,
        });
      }
    });

    test('record a round whose window ran out with no chosen id', () {
      recorder.recordRound(session.rounds.first, chosenId: null, responseMs: 8000);
      final round = recorder.finish(endedAtMs: 1, offline: true).toJson()['rounds']! as List;
      expect((round.single as Map)['chosenId'], isNull);
      expect((round.single as Map)['responseMs'], 8000);
    });

    test('record a hint', () {
      recorder.recordRound(session.rounds.first, chosenId: session.rounds.first.correctId, responseMs: 1500, hintUsed: true);
      final round = recorder.finish(endedAtMs: 1, offline: true).toJson()['rounds']! as List;
      expect((round.single as Map)['hintUsed'], isTrue);
    });

    test('use the question kind names of the payload', () {
      final kinds = {for (final k in QuestionKind.values) k.name};
      expect(kinds, {'song', 'artist', 'era'});
      expect({for (final m in GameMode.values) m.name}, {'intro', 'middle', 'generation'});
      expect({for (final d in Difficulty.values) d.name}, {'easy', 'medium', 'hard'});
    });
  });

  group('recording rounds', () {
    test('rejects an answer that is not one of the options', () {
      final round = session.rounds.first;
      final notAnOption = round.optionIds.reduce(max) + 1000;
      expect(
        () => recorder.recordRound(round, chosenId: notAnOption, responseMs: 1000),
        throwsArgumentError,
      );
    });

    test('rejects a negative response time', () {
      expect(
        () => recorder.recordRound(session.rounds.first, chosenId: null, responseMs: -1),
        throwsArgumentError,
      );
    });

    test('rejects more than 50 rounds', () {
      final round = session.rounds.first;
      for (var i = 0; i < SessionConfig.maxRounds; i++) {
        recorder.recordRound(round, chosenId: null, responseMs: 5000);
      }
      expect(() => recorder.recordRound(round, chosenId: null, responseMs: 5000), throwsStateError);
    });

    test('does not let the caller change what was recorded', () {
      recorder.recordRound(session.rounds.first, chosenId: null, responseMs: 5000);
      expect(() => recorder.rounds.clear(), throwsUnsupportedError);
    });
  });

  test('a session flows from generator to recorder to scorer', () {
    const scorer = Scorer();
    final answers = <RoundAnswer>[];
    for (final r in session.rounds) {
      // Correct on even track ids, wrong otherwise, 2.5 s after the audio started.
      final chosen = r.trackId.isEven ? r.correctId : r.optionIds.firstWhere((id) => id != r.correctId);
      recorder.recordRound(r, chosenId: chosen, responseMs: 2500);
      answers.add(RoundAnswer(correct: r.isCorrect(chosen), responseMs: 2500));
    }
    final payload = recorder.finish(endedAtMs: 1760000095000, offline: true);
    final score = scorer.scoreSession(mode: payload.mode, difficulty: payload.difficulty, answers: answers);

    final correctRounds = answers.where((a) => a.correct).length;
    // Middle mode, hard: base 250, window 8000 ms. 2500 ms: bonus 86, so 336 a round.
    expect(score.total, correctRounds * 336);
    expect(score.flagged, isFalse);
    expect(payload.rounds, hasLength(session.rounds.length));
  });
}
