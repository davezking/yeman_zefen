import '../domain/session_config.dart';

enum SessionPhase { idle, preparing, playing, finished, failed }

enum RoundPhase {
  /// The clip is loading. Nothing to answer yet.
  loading,

  /// Audio is playing and the answer window is running.
  answering,

  /// A call or another app took the audio. Waiting for the player to resume.
  interrupted,

  /// The answer was given (or time ran out) and is shown for a moment.
  feedback,
}

class AnswerOption {
  const AnswerOption({required this.id, required this.label});
  final int id;
  final String label;
}

/// The round on screen.
class RoundView {
  const RoundView({
    required this.number,
    required this.total,
    required this.kind,
    required this.options,
    required this.windowMs,
    required this.phase,
    required this.attempt,
    this.chosenId,
    this.correctId,
    this.points,
    this.timedOut = false,
    this.valid = true,
  });

  /// 1-based position in the session. A skipped round still uses up its number.
  final int number;
  final int total;
  final QuestionKind kind;
  final List<AnswerOption> options;

  /// How long the player has to answer, from the moment audio starts.
  final int windowMs;
  final RoundPhase phase;

  /// 1 for the first play of the round, higher after each resume. A new
  /// attempt restarts the countdown bar.
  final int attempt;

  // Filled in during feedback.
  final int? chosenId;
  final int? correctId;
  final int? points;
  final bool timedOut;

  /// False when the answer was too fast to be a person (under 200 ms).
  final bool valid;

  bool get isCorrect => chosenId != null && chosenId == correctId;
}

/// One played round, for the results list.
class RoundSummary {
  const RoundSummary({
    required this.number,
    required this.kind,
    required this.correctLabel,
    required this.chosenLabel,
    required this.correct,
    required this.points,
    required this.valid,
    required this.responseMs,
  });

  final int number;
  final QuestionKind kind;
  final String correctLabel;

  /// Null when the window ran out.
  final String? chosenLabel;
  final bool correct;
  final int points;
  final bool valid;
  final int responseMs;
}

class SessionSummary {
  const SessionSummary({
    required this.config,
    required this.totalScore,
    required this.rounds,
    required this.skipped,
    required this.flagged,
    required this.bestBefore,
    required this.isNewBest,
    this.saveError,
  });

  final SessionConfig config;
  final int totalScore;
  final List<RoundSummary> rounds;

  /// Rounds left out because their clip was missing or would not play.
  final int skipped;

  /// True when a response was too fast to be a person.
  final bool flagged;

  /// The best score for this mode and era before this session.
  final int? bestBefore;
  final bool isNewBest;

  /// Set when the session could not be saved on the device.
  final String? saveError;
}

class SessionState {
  const SessionState({
    this.phase = SessionPhase.idle,
    this.config,
    this.round,
    this.summary,
    this.error,
  });

  final SessionPhase phase;
  final SessionConfig? config;
  final RoundView? round;
  final SessionSummary? summary;
  final String? error;

  static const idle = SessionState();
}
