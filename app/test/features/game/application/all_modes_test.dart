import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/scorer.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'session_kit.dart';

/// Every way to play plays a full session, and what it sends is what the server scores the same
/// way (the shared fixtures, `docs/fixtures/scoring.json`, hold the server's side of this).
void main() {
  final combinations = <SessionConfig>[
    for (final mode in [GameMode.intro, GameMode.middle])
      for (final difficulty in Difficulty.values)
        for (final questions in QuestionMix.values)
          SessionConfig(mode: mode, difficulty: difficulty, questions: questions, rounds: 4),
    for (final difficulty in Difficulty.values)
      SessionConfig(mode: GameMode.generation, difficulty: difficulty, rounds: 4),
  ];

  test('there are 19 ways to play: 2 modes x 3 difficulties x 3 question choices, and Which Era?', () {
    expect(combinations, hasLength(2 * 3 * 3 + 3));
  });

  for (final config in combinations) {
    final label = '${config.mode.name} / ${config.difficulty.name} / ${config.mode == GameMode.generation ? 'era' : config.questions.name}';

    test('$label plays a full session, scored as the rules say', () async {
      final kit = await SessionKit.create();
      addTearDown(kit.dispose);
      kit.start(config);

      final scorer = const Scorer();
      final windowMs = scorer.windowMs(config.mode, config.difficulty);
      final limitMs = config.mode == GameMode.generation ? Scorer.generationClipMs : config.difficulty.clipLengthMs;
      final kinds = <QuestionKind>{};

      var last = 0;
      var expected = 0;
      while (true) {
        await kit.until(
          () =>
              kit.state.phase == SessionPhase.finished ||
              (kit.state.round?.phase == RoundPhase.answering && kit.state.round!.number > last),
          what: 'the next round',
        );
        if (kit.state.phase == SessionPhase.finished) break;
        final round = kit.state.round!;
        last = round.number;
        kinds.add(round.kind);
        expect(round.windowMs, windowMs);
        expect(kit.voices.firstWhere((v) => v.playing).loads.last.$2, Duration(milliseconds: limitMs));

        final correct = round.kind == QuestionKind.era ? SessionKit.eraOf(kit.playingTrackId()) : kit.correctOption();
        kit.clockMs += 2500;
        expected += scorer.scoreRound(mode: config.mode, difficulty: config.difficulty, correct: true, responseMs: 2500).points;
        kit.controller.answer(correct);
        await kit.untilRound(last, RoundPhase.feedback);
        kit.endFeedback();
      }

      final summary = kit.state.summary!;
      expect(summary.rounds, hasLength(4));
      expect(summary.totalScore, expected);
      expect(summary.rounds.every((r) => r.correct && r.valid), isTrue);

      final row = await kit.db.select(kit.db.pendingSessions).getSingle();
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      expect(payload['mode'], config.mode.name);
      expect(payload['difficulty'], config.difficulty.name);
      expect(payload['generationId'], 0);
      final rounds = (payload['rounds'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(rounds, hasLength(4));
      expect({for (final r in rounds) r['question']}, kinds.map((k) => k.name).toSet());
      if (config.mode == GameMode.generation) {
        expect(kinds, {QuestionKind.era});
      } else if (config.questions == QuestionMix.song) {
        expect(kinds, {QuestionKind.song});
      } else if (config.questions == QuestionMix.artist) {
        expect(kinds, {QuestionKind.artist});
      }
    });
  }
}
