import 'dart:math';

import 'package:yeman_zefen/features/game/domain/game_track.dart';
import 'package:yeman_zefen/features/game/domain/round_generator.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/game/domain/session_payload.dart';

/// 30 tracks over 2 eras and 8 artists.
final fixtureTracks = [
  for (var i = 1; i <= 30; i++) GameTrack(id: i, artistId: 100 + i % 8, generationId: 1 + i % 2),
];

/// A finished payload with [rounds] rounds, every one answered correctly.
SessionPayload payloadOf({
  String id = 'session-1',
  GameMode mode = GameMode.intro,
  int generationId = 0,
  int rounds = 4,
  int seed = 1,
}) {
  final config = SessionConfig(mode: mode, difficulty: Difficulty.medium, generationId: generationId, rounds: rounds);
  final session = RoundGenerator(fixtureTracks, rng: Random(seed)).generate(config);
  final recorder = SessionRecorder(id: id, config: config, startedAtMs: 1000);
  for (final r in session.rounds) {
    recorder.recordRound(r, chosenId: r.correctId, responseMs: 2500);
  }
  return recorder.finish(endedAtMs: 2000, offline: true);
}
