import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/domain/game_track.dart';
import 'package:yeman_zefen/features/game/domain/generated_session.dart';
import 'package:yeman_zefen/features/game/domain/round_generator.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

/// Tracks for the given eras. `eras[era]` is (tracks, artists): the tracks are
/// spread over that many artists. Ids and artist ids are unique across eras.
List<GameTrack> makeTracks(Map<int, (int, int)> eras) {
  final tracks = <GameTrack>[];
  var id = 1;
  eras.forEach((era, spec) {
    final (count, artists) = spec;
    for (var i = 0; i < count; i++) {
      tracks.add(GameTrack(id: id++, artistId: era * 100 + (i % artists), generationId: era));
    }
  });
  return tracks;
}

SessionConfig config({
  GameMode mode = GameMode.intro,
  Difficulty difficulty = Difficulty.medium,
  int generationId = 0,
  QuestionMix questions = QuestionMix.mixed,
  int rounds = 10,
}) =>
    SessionConfig(
      mode: mode,
      difficulty: difficulty,
      generationId: generationId,
      questions: questions,
      rounds: rounds,
    );

void main() {
  /// Five eras with plenty of tracks and artists in each.
  final plenty = makeTracks({for (var e = 1; e <= 5; e++) e: (12, 6)});
  final eraOfTrack = {for (final t in plenty) t.id: t.generationId};
  final artistOfTrack = {for (final t in plenty) t.id: t.artistId};
  final eraOfArtist = {for (final t in plenty) t.artistId: t.generationId};

  RoundGenerator generator(List<GameTrack> tracks, [int seed = 1]) =>
      RoundGenerator(tracks, rng: Random(seed));

  group('a session', () {
    test('has 10 rounds with no track repeated', () {
      final session = generator(plenty).generate(config());
      expect(session.rounds, hasLength(10));
      expect(session.rounds.map((r) => r.trackId).toSet(), hasLength(10));
    });

    test('has as many rounds as asked', () {
      expect(generator(plenty).generate(config(rounds: 4)).rounds, hasLength(4));
    });

    test('is shorter, without repeats, when there are not enough tracks in the era', () {
      final session = generator(plenty).generate(config(generationId: 2, rounds: 20));
      expect(session.rounds, hasLength(12));
      expect(session.rounds.map((r) => r.trackId).toSet(), hasLength(12));
    });

    test('keeps its config', () {
      final c = config(mode: GameMode.middle, difficulty: Difficulty.hard);
      expect(generator(plenty).generate(c).config, same(c));
    });

    test('only asks about tracks of the chosen era', () {
      final session = generator(plenty).generate(config(generationId: 3, rounds: 12));
      for (final r in session.rounds) {
        expect(eraOfTrack[r.trackId], 3);
      }
    });

    test('draws from every era when the era is "all"', () {
      final eras = <int?>{};
      for (var seed = 0; seed < 20; seed++) {
        for (final r in generator(plenty, seed).generate(config()).rounds) {
          eras.add(eraOfTrack[r.trackId]);
        }
      }
      expect(eras, {1, 2, 3, 4, 5});
    });
  });

  group('options', () {
    test('are 4 distinct ids that include the correct one, for every question kind', () {
      for (var seed = 0; seed < 30; seed++) {
        final session = generator(plenty, seed).generate(config());
        for (final r in session.rounds) {
          expect(r.optionIds, hasLength(4), reason: 'seed $seed');
          expect(r.optionIds.toSet(), hasLength(4), reason: 'seed $seed');
          expect(r.optionIds, contains(r.correctId), reason: 'seed $seed');
        }
      }
    });

    test('are not always in the same order', () {
      final positions = <int>{};
      for (var seed = 0; seed < 10; seed++) {
        for (final r in generator(plenty, seed).generate(config(questions: QuestionMix.song)).rounds) {
          positions.add(r.optionIds.indexOf(r.correctId));
        }
      }
      expect(positions, {0, 1, 2, 3});
    });
  });

  group('song questions', () {
    final session = generator(plenty).generate(config(questions: QuestionMix.song, rounds: 12));

    test('offer track ids, and the right one is the track played', () {
      for (final r in session.rounds) {
        expect(r.kind, QuestionKind.song);
        expect(r.correctId, r.trackId);
        for (final id in r.optionIds) {
          expect(eraOfTrack.containsKey(id), isTrue, reason: '$id is not an installed track');
        }
      }
    });

    test('use distractors from the same era when it has enough tracks', () {
      for (final r in session.rounds) {
        for (final id in r.optionIds) {
          expect(eraOfTrack[id], eraOfTrack[r.trackId]);
        }
        expect(r.distractorFallback, 0);
      }
      expect(session.distractorFallback, 0);
    });
  });

  group('artist questions', () {
    final session = generator(plenty).generate(config(questions: QuestionMix.artist, rounds: 12));

    test('offer artist ids, and the right one is the artist of the track played', () {
      for (final r in session.rounds) {
        expect(r.kind, QuestionKind.artist);
        expect(r.correctId, artistOfTrack[r.trackId]);
        for (final id in r.optionIds) {
          expect(eraOfArtist.containsKey(id), isTrue, reason: '$id is not an artist');
        }
      }
    });

    test('offer 4 distinct artists from the same era when it has enough', () {
      for (final r in session.rounds) {
        expect(r.optionIds.toSet(), hasLength(4));
        for (final id in r.optionIds) {
          expect(eraOfArtist[id], eraOfTrack[r.trackId]);
        }
        expect(r.distractorFallback, 0);
      }
    });

    test('count an artist by id, so one artist with many tracks is offered once', () {
      // Era 1 has 12 tracks by 4 artists, so every round needs all 4 artists.
      final few = makeTracks({1: (12, 4), 2: (12, 6)});
      final s = generator(few).generate(config(generationId: 1, questions: QuestionMix.artist, rounds: 12));
      for (final r in s.rounds) {
        expect(r.optionIds.toSet(), hasLength(4));
        expect(r.distractorFallback, 0);
      }
    });
  });

  group('mixed questions', () {
    test('contain both kinds', () {
      final kinds = <QuestionKind>{};
      for (var seed = 0; seed < 10; seed++) {
        kinds.addAll(generator(plenty, seed).generate(config()).rounds.map((r) => r.kind));
      }
      expect(kinds, {QuestionKind.song, QuestionKind.artist});
    });
  });

  group('fallback to other eras', () {
    test('an era with only 3 artists still gives valid artist questions', () {
      // Era 2 has 3 artists. Eras 1 and 3 are adjacent. Era 5 is not.
      final tracks = makeTracks({1: (6, 5), 2: (9, 3), 3: (6, 5), 5: (6, 5)});
      final adjacentArtists = {
        for (final t in tracks)
          if (t.generationId == 1 || t.generationId == 3) t.artistId,
      };
      final era2Artists = {
        for (final t in tracks)
          if (t.generationId == 2) t.artistId,
      };
      final artistOf = {for (final t in tracks) t.id: t.artistId};

      for (var seed = 0; seed < 10; seed++) {
        final session = generator(tracks, seed)
            .generate(config(generationId: 2, questions: QuestionMix.artist, rounds: 9));
        expect(session.rounds, hasLength(9));
        for (final r in session.rounds) {
          expect(r.optionIds.toSet(), hasLength(4), reason: 'seed $seed');
          expect(r.correctId, artistOf[r.trackId]);
          final outside = r.optionIds.where((id) => !era2Artists.contains(id)).toList();
          expect(outside, hasLength(1), reason: 'two same-era distractors, one fallback');
          expect(adjacentArtists, contains(outside.single), reason: 'the fallback comes from an adjacent era');
          expect(r.distractorFallback, 1);
        }
        expect(session.distractorFallback, 9);
      }
    });

    test('goes to any era when the adjacent ones are short too', () {
      // Era 1 has one artist, era 2 (adjacent) has one, era 5 has plenty.
      final tracks = makeTracks({1: (4, 1), 2: (4, 1), 5: (8, 6)});
      final era2Artist = tracks.firstWhere((t) => t.generationId == 2).artistId;
      final era5Artists = {
        for (final t in tracks)
          if (t.generationId == 5) t.artistId,
      };

      final session = generator(tracks)
          .generate(config(generationId: 1, questions: QuestionMix.artist, rounds: 4));
      for (final r in session.rounds) {
        expect(r.optionIds.toSet(), hasLength(4));
        expect(r.optionIds, contains(era2Artist), reason: 'the adjacent era is used before any other');
        expect(r.optionIds.where(era5Artists.contains), hasLength(2));
        expect(r.distractorFallback, 3);
      }
    });

    test('song questions fall back the same way and count the fallbacks', () {
      // Era 3 has 2 tracks: one same-era distractor, two from elsewhere.
      final tracks = makeTracks({2: (3, 3), 3: (2, 2), 4: (3, 3), 5: (3, 3)});
      final session = generator(tracks)
          .generate(config(generationId: 3, questions: QuestionMix.song, rounds: 2));
      final era = {for (final t in tracks) t.id: t.generationId};
      for (final r in session.rounds) {
        final sameEra = r.optionIds.where((id) => era[id] == 3).length;
        expect(sameEra, 2, reason: 'the track itself and the other era-3 track');
        expect(r.distractorFallback, 2);
        // Adjacent eras (2 and 4) are used before era 5.
        expect(r.optionIds.where((id) => era[id] == 5), isEmpty);
      }
      expect(session.distractorFallback, 4);
    });

    test('a track with no era gets distractors from any era', () {
      final tracks = [
        const GameTrack(id: 1, artistId: 1),
        ...makeTracks({1: (4, 4)}).map((t) => GameTrack(id: t.id + 10, artistId: t.artistId, generationId: 1)),
      ];
      final session = generator(tracks).generate(config(questions: QuestionMix.song, rounds: 5));
      final noEra = session.rounds.firstWhere((r) => r.trackId == 1);
      expect(noEra.optionIds.toSet(), hasLength(4));
      expect(noEra.distractorFallback, 3);
    });

    test('the session total adds up the rounds', () {
      final tracks = makeTracks({1: (6, 3), 2: (6, 5)});
      final session = generator(tracks)
          .generate(config(generationId: 1, questions: QuestionMix.artist, rounds: 6));
      expect(session.distractorFallback, session.rounds.fold<int>(0, (s, r) => s + r.distractorFallback));
      expect(session.distractorFallback, greaterThan(0));
    });
  });

  group('when the installed tracks are not enough', () {
    test('fewer than 4 tracks cannot make 4 options', () {
      final tracks = makeTracks({1: (3, 3)});
      expect(() => generator(tracks).generate(config()), throwsA(isA<RoundGenerationException>()));
    });

    test('artist questions need 4 artists in total', () {
      final tracks = makeTracks({1: (6, 3), 2: (6, 3)}); // 6 artists across eras, 3 here
      final threeArtists = tracks.where((t) => t.artistId % 100 < 3 && t.generationId == 1).toList();
      expect(
        () => generator(threeArtists + [const GameTrack(id: 99, artistId: 100, generationId: 1)])
            .generate(config(questions: QuestionMix.artist)),
        throwsA(isA<RoundGenerationException>()),
      );
    });

    test('mixed questions become song questions when there are fewer than 4 artists', () {
      final tracks = [
        for (var i = 1; i <= 8; i++) GameTrack(id: i, artistId: 1 + i % 3, generationId: 1),
      ];
      final session = generator(tracks).generate(config(rounds: 8));
      expect(session.rounds.every((r) => r.kind == QuestionKind.song), isTrue);
      expect(session.rounds.every((r) => r.optionIds.toSet().length == 4), isTrue);
    });

    test('an era with no tracks cannot be played', () {
      expect(
        () => generator(plenty).generate(config(generationId: 9)),
        throwsA(isA<RoundGenerationException>()),
      );
    });

    test('generation mode has no generator yet', () {
      expect(
        () => generator(plenty).generate(config(mode: GameMode.generation)),
        throwsArgumentError,
      );
    });
  });

  group('recently played tracks', () {
    final twenty = makeTracks({1: (20, 8)});
    Set<int> ids(Iterable<int> r) => r.toSet();

    test('are avoided when there are enough others', () {
      final recent = [
        [for (var i = 1; i <= 4; i++) i],
        [for (var i = 5; i <= 8; i++) i],
        [for (var i = 9; i <= 12; i++) i],
      ];
      for (var seed = 0; seed < 10; seed++) {
        final session = generator(twenty, seed).generate(config(rounds: 8), recentSessions: recent);
        expect(ids(session.rounds.map((r) => r.trackId)), {for (var i = 13; i <= 20; i++) i});
      }
    });

    test('are used to fill the session when there are not enough others', () {
      final recent = [
        [for (var i = 1; i <= 12; i++) i],
      ];
      final session = generator(twenty).generate(config(), recentSessions: recent);
      final played = ids(session.rounds.map((r) => r.trackId));
      expect(played, hasLength(10));
      expect(played.containsAll({for (var i = 13; i <= 20; i++) i}), isTrue, reason: 'every unseen track is used');
      expect(played.where((id) => id <= 12), hasLength(2));
    });

    test('count only the last 3 sessions', () {
      final recent = [
        [1, 2, 3, 4],
        [5, 6, 7, 8],
        [9, 10, 11, 12],
        [13, 14, 15, 16, 17, 18, 19, 20], // a 4th session back: ignored
      ];
      // Tracks 1-12 are in the last 3 sessions. 13-20 were only in the 4th, so they count as unseen.
      for (var seed = 0; seed < 10; seed++) {
        final session = generator(twenty, seed).generate(config(rounds: 8), recentSessions: recent);
        expect(ids(session.rounds.map((r) => r.trackId)), {for (var i = 13; i <= 20; i++) i}, reason: 'seed $seed');
      }
    });
  });

  group('randomness', () {
    List<List<Object>> shape(GeneratedSession s) =>
        [for (final r in s.rounds) [r.trackId, r.kind.name, ...r.optionIds]];

    test('the same seed gives the same session', () {
      expect(shape(generator(plenty, 42).generate(config())), shape(generator(plenty, 42).generate(config())));
    });

    test('different seeds give different sessions', () {
      expect(shape(generator(plenty, 1).generate(config())), isNot(shape(generator(plenty, 2).generate(config()))));
    });
  });

  test('a track installed in two packs is treated as one track', () {
    final tracks = [...makeTracks({1: (6, 6)}), ...makeTracks({1: (6, 6)})];
    final session = generator(tracks).generate(config(questions: QuestionMix.song, rounds: 6));
    expect(session.rounds.map((r) => r.trackId).toSet(), hasLength(6));
    for (final r in session.rounds) {
      expect(r.optionIds.toSet(), hasLength(4));
    }
  });
}
