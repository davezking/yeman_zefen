/// What a session plays. The names are the strings in the session payload
/// (`docs/session-payload.md`), so `.name` is the wire value.
enum GameMode { intro, middle, generation }

enum Difficulty { easy, medium, hard }

/// What one round asks. `era` is the generation-guess mode (FR-12).
enum QuestionKind { song, artist, era }

/// What the player picks for a session: one kind, or a mix of song and artist.
enum QuestionMix { song, artist, mixed }

extension DifficultyClip on Difficulty {
  /// How much of the clip plays: 10 s easy, 5 s medium, 3 s hard (FR-7).
  int get clipLengthMs => switch (this) {
        Difficulty.easy => 10000,
        Difficulty.medium => 5000,
        Difficulty.hard => 3000,
      };
}

class SessionConfig {
  const SessionConfig({
    required this.mode,
    required this.difficulty,
    this.generationId = 0,
    this.questions = QuestionMix.mixed,
    this.rounds = defaultRounds,
  })  : assert(rounds >= 1 && rounds <= maxRounds),
        assert(generationId >= 0);

  static const defaultRounds = 10;

  /// The server rejects sessions with more rounds than this.
  static const maxRounds = 50;

  final GameMode mode;
  final Difficulty difficulty;

  /// The era to play, or 0 for all eras. Matches the leaderboard's convention.
  final int generationId;
  final QuestionMix questions;
  final int rounds;
}
