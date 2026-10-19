import 'session_config.dart';

/// One question: which clip plays and the four answers to choose from.
class GeneratedRound {
  GeneratedRound({
    required this.trackId,
    required this.kind,
    required this.correctId,
    required List<int> optionIds,
    this.distractorFallback = 0,
  }) : optionIds = List.unmodifiable(optionIds);

  final int trackId;
  final QuestionKind kind;

  /// The right answer: the track's id for a `song` question, its artist's id
  /// for an `artist` question, its era's id for an `era` question.
  final int correctId;

  /// Four distinct ids in random order, including [correctId] (fewer only for an `era` question
  /// when there are fewer than four eras).
  final List<int> optionIds;

  /// How many of the 3 distractors came from outside the track's own era.
  final int distractorFallback;

  bool isCorrect(int? chosenId) => chosenId != null && chosenId == correctId;
}

class GeneratedSession {
  GeneratedSession({required this.config, required List<GeneratedRound> rounds})
      : rounds = List.unmodifiable(rounds);

  final SessionConfig config;

  /// Up to `config.rounds`. Fewer when there are not enough distinct tracks.
  final List<GeneratedRound> rounds;

  /// Distractors that had to come from another era, over the whole session.
  int get distractorFallback => rounds.fold(0, (sum, r) => sum + r.distractorFallback);
}
