import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'session_kit.dart';

/// Which Era? (FR-12): the engine plays 10 s of the intro, asks for the song's era, and scores it
/// as generation mode (`docs/scoring.md`).
const _era = SessionConfig(mode: GameMode.generation, difficulty: Difficulty.hard, questions: QuestionMix.song, rounds: 3);

void main() {
  late SessionKit kit;

  setUp(() async {
    kit = await SessionKit.create();
  });

  tearDown(() => kit.dispose());

  /// The era the song on screen is from (the kit's tracks alternate between eras 1 and 2).
  int correctEra() => SessionKit.eraOf(kit.playingTrackId());

  test('asks which era, with four eras to pick from', () async {
    kit.start(_era);
    final round = await kit.untilRound(1, RoundPhase.answering);
    expect(round.kind, QuestionKind.era);
    expect(round.options, hasLength(4));
    expect(round.options.map((o) => o.id).toSet(), hasLength(4));
    expect(round.options.map((o) => o.id), contains(correctEra()));
    expect(round.options.every((o) => o.id >= 1 && o.id <= 5), isTrue);
  });

  test('plays 10 s of the intro whatever the difficulty, in a 15 s window', () async {
    kit.start(_era);
    final round = await kit.untilRound(1, RoundPhase.answering);
    expect(round.windowMs, 15000);
    final (path, limit) = kit.voices.firstWhere((v) => v.playing).loads.last;
    expect(limit, const Duration(milliseconds: 10000));
    expect(path, contains('-intro'), reason: 'generation mode has no clip of its own');
  });

  test('scores a right answer as generation mode: 120 plus the speed bonus (E15)', () async {
    kit.start(_era);
    await kit.untilRound(1, RoundPhase.answering);
    final era = correctEra();
    kit.clockMs += 3000;
    kit.controller.answer(era);
    final round = await kit.untilRound(1, RoundPhase.feedback);
    expect((round.points, round.speedBonus, round.correctId), (168, 48, era));
    expect(round.score, 168);
  });

  test('a wrong era scores 0 and shows the right one', () async {
    kit.start(_era);
    await kit.untilRound(1, RoundPhase.answering);
    final era = correctEra();
    final wrong = kit.state.round!.options.firstWhere((o) => o.id != era).id;
    kit.clockMs += 3000;
    kit.controller.answer(wrong);
    final round = await kit.untilRound(1, RoundPhase.feedback);
    expect((round.points, round.isCorrect, round.correctId), (0, false, era));
  });

  test('running out of time scores 0', () async {
    kit.start(_era);
    await kit.untilRound(1, RoundPhase.answering);
    kit.endWindow(15000);
    final round = await kit.untilRound(1, RoundPhase.feedback);
    expect((round.timedOut, round.points), (true, 0));
  });

  test('a full session is for all eras, sends era questions, and lists the song with the era chosen', () async {
    kit.start(_era);
    await kit.playAll(pick: correctEra, responseMs: 3000);

    final summary = kit.state.summary!;
    expect(summary.rounds, hasLength(3));
    expect(summary.totalScore, 3 * 168);
    expect(summary.rounds.every((r) => r.kind == QuestionKind.era && r.correct), isTrue);
    expect(summary.rounds.first.correctName.latin, startsWith('Song '), reason: 'the results name the song that played');
    expect(summary.rounds.first.correctEraId, isIn([1, 2]));
    expect(summary.rounds.first.chosenEraId, summary.rounds.first.correctEraId);

    final row = await kit.db.select(kit.db.pendingSessions).getSingle();
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    expect(payload['mode'], 'generation');
    expect(payload['generationId'], 0, reason: 'era sessions count on the all-eras boards');
    final rounds = (payload['rounds'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(rounds.every((r) => r['question'] == 'era' && (r['optionIds'] as List).length == 4), isTrue);
  });

  test('fails with "too few songs" when no song has an era', () async {
    await kit.dispose();
    kit = await SessionKit.create(tracks: 6, eras: false);
    kit.start(_era);
    await kit.untilPhase(SessionPhase.failed);
    expect(kit.state.error?.problem, SessionProblem.tooFewSongs);
  });
}
