import 'generated_session.dart';
import 'session_config.dart';

/// One round as it is sent to the server. The server recomputes the score from
/// these events, so the correct answer is not part of it.
class RoundRecord {
  const RoundRecord({
    required this.trackId,
    required this.question,
    required this.optionIds,
    required this.chosenId,
    required this.responseMs,
    required this.hintUsed,
  });

  final int trackId;
  final QuestionKind question;
  final List<int> optionIds;

  /// The option the player tapped, or null when the answer window ran out.
  final int? chosenId;
  final int responseMs;
  final bool hintUsed;

  Map<String, Object?> toJson() => {
        'trackId': trackId,
        'question': question.name,
        'optionIds': optionIds,
        'chosenId': chosenId,
        'responseMs': responseMs,
        'hintUsed': hintUsed,
      };
}

/// A finished session, in the shape of `POST /v1/sessions`
/// (`docs/session-payload.md`).
class SessionPayload {
  const SessionPayload({
    required this.id,
    required this.mode,
    required this.generationId,
    required this.difficulty,
    required this.clientStartedAt,
    required this.clientEndedAt,
    required this.offline,
    required this.rounds,
    required this.interstitialShown,
    required this.rewardedCompleted,
  });

  final String id;
  final GameMode mode;
  final int generationId;
  final Difficulty difficulty;
  final int clientStartedAt;
  final int clientEndedAt;
  final bool offline;
  final List<RoundRecord> rounds;
  final int interstitialShown;
  final int rewardedCompleted;

  Map<String, Object?> toJson() => {
        'id': id,
        'mode': mode.name,
        'generationId': generationId,
        'difficulty': difficulty.name,
        'clientStartedAt': clientStartedAt,
        'clientEndedAt': clientEndedAt,
        'offline': offline,
        'rounds': [for (final r in rounds) r.toJson()],
        'ads': {
          'interstitialShown': interstitialShown,
          'rewardedCompleted': rewardedCompleted,
        },
      };
}

/// Collects the rounds of one session and builds its payload.
class SessionRecorder {
  /// [id] is a UUID made by the caller. It is the server's idempotency key, so
  /// it is generated once per session and reused if the upload is retried.
  SessionRecorder({
    required this.id,
    required this.config,
    required this.startedAtMs,
  });

  final String id;
  final SessionConfig config;
  final int startedAtMs;

  final _rounds = <RoundRecord>[];

  List<RoundRecord> get rounds => List.unmodifiable(_rounds);

  /// Records how a round went. [chosenId] is null when the window ran out.
  /// [responseMs] is measured from the moment audio actually started.
  void recordRound(
    GeneratedRound round, {
    required int? chosenId,
    required int responseMs,
    bool hintUsed = false,
  }) {
    if (chosenId != null && !round.optionIds.contains(chosenId)) {
      throw ArgumentError.value(chosenId, 'chosenId', 'is not one of the round options');
    }
    if (responseMs < 0) {
      throw ArgumentError.value(responseMs, 'responseMs', 'must not be negative');
    }
    if (_rounds.length >= SessionConfig.maxRounds) {
      throw StateError('a session has at most ${SessionConfig.maxRounds} rounds');
    }
    _rounds.add(
      RoundRecord(
        trackId: round.trackId,
        question: round.kind,
        optionIds: round.optionIds,
        chosenId: chosenId,
        responseMs: responseMs,
        hintUsed: hintUsed,
      ),
    );
  }

  /// [offline] is whether the device had no connection for the session.
  SessionPayload finish({
    required int endedAtMs,
    required bool offline,
    int interstitialShown = 0,
    int rewardedCompleted = 0,
  }) {
    return SessionPayload(
      id: id,
      mode: config.mode,
      generationId: config.generationId,
      difficulty: config.difficulty,
      clientStartedAt: startedAtMs,
      clientEndedAt: endedAtMs,
      offline: offline,
      rounds: rounds,
      interstitialShown: interstitialShown,
      rewardedCompleted: rewardedCompleted,
    );
  }
}
