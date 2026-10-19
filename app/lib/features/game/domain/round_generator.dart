import 'dart:math';

import 'eras.dart';
import 'game_track.dart';
import 'generated_session.dart';
import 'session_config.dart';

enum RoundGenerationReason { tooFewTracks, tooFewArtists, noTracksInEra }

/// The installed packs cannot make the session that was asked for.
class RoundGenerationException implements Exception {
  const RoundGenerationException(this.message, this.reason);
  final String message;
  final RoundGenerationReason reason;

  @override
  String toString() => 'RoundGenerationException: $message';
}

/// Builds the rounds of a session from the installed tracks. Pure Dart: the
/// only source of randomness is [rng], so a seeded one gives the same session.
class RoundGenerator {
  /// A track in more than one pack is the same track, so it is kept once.
  RoundGenerator(Iterable<GameTrack> tracks, {Random? rng})
      : _tracks = List.unmodifiable({for (final t in tracks) t.id: t}.values),
        _rng = rng ?? Random();

  final List<GameTrack> _tracks;
  final Random _rng;

  /// Options per question (FR-8).
  static const optionCount = 4;

  /// How many past sessions' tracks are avoided when choosing new ones.
  static const historySessions = 3;

  /// Makes a session.
  ///
  /// [recentSessions] holds the track ids played in earlier sessions, newest
  /// first. Only the first [historySessions] count. Tracks outside them come
  /// first, but older ones are used when there are not enough.
  ///
  /// [playable] limits which tracks a round can be about; every track still supplies wrong
  /// answers. Null means all of them. The catalog is the whole pool for distractors, so a
  /// session can ask about a few clips that are on the device and still have four answers.
  GeneratedSession generate(
    SessionConfig config, {
    List<Iterable<int>> recentSessions = const [],
    Set<int>? playable,
  }) {
    if (config.mode == GameMode.generation) return _generateEraSession(config, recentSessions, playable);
    if (_tracks.length < optionCount) {
      throw RoundGenerationException(
        'need at least $optionCount tracks for 4 options, have ${_tracks.length}',
        RoundGenerationReason.tooFewTracks,
      );
    }

    final pool = [
      for (final t in _tracks)
        if ((config.generationId == 0 || t.generationId == config.generationId) &&
            (playable == null || playable.contains(t.id)))
          t,
    ];
    if (pool.isEmpty) {
      throw RoundGenerationException(
        'no playable tracks in era ${config.generationId}',
        RoundGenerationReason.noTracksInEra,
      );
    }

    final artistCount = _tracks.map((t) => t.artistId).toSet().length;
    final canAskArtist = artistCount >= optionCount;
    if (config.questions == QuestionMix.artist && !canAskArtist) {
      throw RoundGenerationException(
        'need at least $optionCount artists for artist questions, have $artistCount',
        RoundGenerationReason.tooFewArtists,
      );
    }

    final chosen = _chooseTracks(pool, config.rounds, recentSessions);
    return GeneratedSession(
      config: config,
      rounds: [
        for (final track in chosen)
          roundFor(track, _kindFor(config.questions, canAskArtist)),
      ],
    );
  }

  /// The generation-guess session (FR-12): each round plays a track and asks which era it is from.
  /// It has no era filter and no question mix: the answer would give the filter away, and every
  /// round is an era question. Only tracks with one of the known eras ([eraIds]) can be asked about.
  GeneratedSession _generateEraSession(
    SessionConfig config,
    List<Iterable<int>> recentSessions,
    Set<int>? playable,
  ) {
    final pool = [
      for (final t in _tracks)
        if (eraIds.contains(t.generationId) && (playable == null || playable.contains(t.id))) t,
    ];
    if (pool.isEmpty) {
      throw const RoundGenerationException(
        'no playable tracks with an era',
        RoundGenerationReason.noTracksInEra,
      );
    }
    final chosen = _chooseTracks(pool, config.rounds, recentSessions);
    return GeneratedSession(
      config: config,
      rounds: [for (final track in chosen) roundFor(track, QuestionKind.era)],
    );
  }

  /// A round about [track] with fresh options, by the same rules as [generate]: same-era wrong
  /// answers first, and distinct artists for an artist question. The prefetcher uses this to put
  /// another track in a round whose clip did not arrive in time.
  GeneratedRound roundFor(GameTrack track, QuestionKind kind) => _buildRound(track, kind);

  /// Tracks not seen recently first, then the rest, each in random order.
  /// A track appears at most once.
  List<GameTrack> _chooseTracks(
    List<GameTrack> pool,
    int count,
    List<Iterable<int>> recentSessions,
  ) {
    final recent = {for (final s in recentSessions.take(historySessions)) ...s};
    final unseen = [for (final t in pool) if (!recent.contains(t.id)) t]..shuffle(_rng);
    final seen = [for (final t in pool) if (recent.contains(t.id)) t]..shuffle(_rng);
    final chosen = [...unseen, ...seen].take(count).toList()..shuffle(_rng);
    return chosen;
  }

  QuestionKind _kindFor(QuestionMix mix, bool canAskArtist) => switch (mix) {
        QuestionMix.song => QuestionKind.song,
        QuestionMix.artist => QuestionKind.artist,
        QuestionMix.mixed => canAskArtist && _rng.nextBool() ? QuestionKind.artist : QuestionKind.song,
      };

  /// An era question: the track's era and three others, all distinct. With fewer than four eras in
  /// all, every era is an option.
  GeneratedRound _buildEraRound(GameTrack track) {
    final correctId = track.generationId;
    if (correctId == null || !eraIds.contains(correctId)) {
      throw ArgumentError.value(track.id, 'track', 'has no known era to ask about');
    }
    // Only the eras the app can name: an id it does not know would read as "All eras".
    final others = [for (final e in eraIds) if (e != correctId) e]..shuffle(_rng);
    final options = [correctId, ...others.take(optionCount - 1)]..shuffle(_rng);
    return GeneratedRound(
      trackId: track.id,
      kind: QuestionKind.era,
      correctId: correctId,
      optionIds: options,
    );
  }

  GeneratedRound _buildRound(GameTrack track, QuestionKind kind) {
    if (kind == QuestionKind.era) return _buildEraRound(track);
    final picked = kind == QuestionKind.artist ? _artistDistractors(track) : _songDistractors(track);
    final correctId = kind == QuestionKind.artist ? track.artistId : track.id;
    final options = [correctId, ...picked.ids]..shuffle(_rng);
    return GeneratedRound(
      trackId: track.id,
      kind: kind,
      correctId: correctId,
      optionIds: options,
      distractorFallback: picked.fallback,
    );
  }

  /// 0 for the track's own era, 1 for an adjacent era, 2 for any other.
  /// A track with no era counts only as "any" to a track that has one.
  static int _tier(int? correctEra, int? candidateEra) {
    if (correctEra == null && candidateEra == null) return 0;
    if (correctEra == null || candidateEra == null) return 2;
    final distance = (correctEra - candidateEra).abs();
    return distance == 0 ? 0 : (distance == 1 ? 1 : 2);
  }

  ({List<int> ids, int fallback}) _songDistractors(GameTrack correct) {
    final tiers = List.generate(3, (_) => <int>[]);
    for (final t in _tracks) {
      if (t.id == correct.id) continue;
      tiers[_tier(correct.generationId, t.generationId)].add(t.id);
    }
    return _fill(tiers);
  }

  ({List<int> ids, int fallback}) _artistDistractors(GameTrack correct) {
    // An artist takes the closest tier any of their tracks reaches.
    final bestTier = <int, int>{};
    for (final t in _tracks) {
      if (t.artistId == correct.artistId) continue;
      final tier = _tier(correct.generationId, t.generationId);
      final known = bestTier[t.artistId];
      if (known == null || tier < known) bestTier[t.artistId] = tier;
    }
    final tiers = List.generate(3, (_) => <int>[]);
    bestTier.forEach((artistId, tier) => tiers[tier].add(artistId));
    return _fill(tiers);
  }

  /// Takes distractors from the closest tier first, in random order within a
  /// tier. Everything outside tier 0 counts as a fallback.
  ({List<int> ids, int fallback}) _fill(List<List<int>> tiers) {
    const needed = optionCount - 1;
    final ids = <int>[];
    var fallback = 0;
    for (var tier = 0; tier < tiers.length && ids.length < needed; tier++) {
      final candidates = tiers[tier]..shuffle(_rng);
      for (final id in candidates) {
        if (ids.length == needed) break;
        ids.add(id);
        if (tier > 0) fallback++;
      }
    }
    // generate() checks there are enough tracks and artists in total.
    assert(ids.length == needed);
    return (ids: ids, fallback: fallback);
  }
}
