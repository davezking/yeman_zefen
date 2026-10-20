import '../../../core/l10n/display_name.dart';
import '../domain/session_config.dart';

enum SessionPhase {
  idle,
  preparing,

  /// Offline, and every song on the phone was played recently. Waiting for the player to play
  /// them again (`SessionController.playAgain`) or leave for Offline play.
  outOfSongs,
  playing,
  finished,
  failed,
}

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

/// A full-screen ad covering the round.
enum RoundAd {
  none,

  /// Between rounds, after the feedback.
  interstitial,

  /// The rewarded ad behind the hint. The answer window is paused.
  rewarded,
}

/// What the player is told after asking for a hint that did not come.
enum HintNotice {
  /// The rewarded ad was closed before the reward.
  notFinished,

  /// No ad could be shown.
  unavailable,
}

class AnswerOption {
  const AnswerOption({required this.id, required this.name});
  final int id;

  /// The song or artist, in both scripts. The screen picks one for the UI language.
  final DisplayName name;
}

/// The round on screen.
class RoundView {
  const RoundView({
    required this.number,
    required this.total,
    required this.kind,
    required this.options,
    required this.windowMs,
    int? remainingMs,
    required this.phase,
    required this.attempt,
    this.chosenId,
    this.correctId,
    this.points,
    this.timedOut = false,
    this.valid = true,
    this.score = 0,
    this.speedBonus = 0,
    this.trackName = const DisplayName(),
    this.artistName = const DisplayName(),
    this.clipPlaying = false,
    this.answerClockStartMs,
    this.feedbackStartedAtMs,
    this.feedbackMs = 0,
    this.hintAsked = false,
    this.hintUsed = false,
    this.removedIds = const {},
    this.hintSheetOpenedAtMs,
    this.hintSheetMs = 0,
    this.hintNotice,
    this.hintNoticeId = 0,
  }) : remainingMs = remainingMs ?? windowMs;

  /// 1-based position in the session. A skipped round still uses up its number.
  final int number;
  final int total;
  final QuestionKind kind;
  final List<AnswerOption> options;

  /// How long the player has to answer, from the moment audio starts.
  final int windowMs;

  /// What is left of the window when this attempt starts. Less than [windowMs]
  /// after a pause, because the time used before it still counts.
  final int remainingMs;
  final RoundPhase phase;

  /// 1 for the first play of the round, higher after each resume. A new
  /// attempt restarts the countdown bar from [remainingMs].
  final int attempt;

  // Filled in during feedback.
  final int? chosenId;
  final int? correctId;
  final int? points;
  final bool timedOut;

  /// False when the answer was too fast to be a person (under 200 ms).
  final bool valid;

  /// The running score, including this round once it is answered.
  final int score;

  /// The part of [points] that came from answering fast. Filled in during feedback.
  final int speedBonus;

  /// The round's song and its singer, for "It was Song · Artist". Empty while loading.
  final DisplayName trackName;
  final DisplayName artistName;

  /// The clip is audibly playing now: true from the start of the answer window until the clip
  /// ends, which can be before the window does.
  final bool clipPlaying;

  /// While answering: the monotonic time at which this round's answer clock started, moved back by
  /// the time used before a pause, so `now - answerClockStartMs` is the time used so far.
  final int? answerClockStartMs;

  /// During feedback: when it began (monotonic ms) and how long it lasts. A right answer moves on
  /// by itself; a wrong one or a time-out can be skipped by a tap.
  final int? feedbackStartedAtMs;
  final int feedbackMs;

  /// The player has asked for this round's hint (one try a round).
  final bool hintAsked;

  /// A rewarded ad removed two wrong options ([removedIds]) this round; its points are halved.
  final bool hintUsed;
  final Set<int> removedIds;

  /// While the hint sheet is open: when it opened (monotonic ms) and how long it stays open. The
  /// answer window is paused meanwhile.
  final int? hintSheetOpenedAtMs;
  final int hintSheetMs;

  /// The last hint that did not come, and a number that changes with each one, so the screen tells
  /// the player once.
  final HintNotice? hintNotice;
  final int hintNoticeId;

  bool get isCorrect => chosenId != null && chosenId == correctId;

  /// The round can offer a hint: answering, with the hint not asked for yet and the sheet closed.
  /// The button shows only while a rewarded ad is also loaded and no ad covers the round.
  bool get hintOffered => phase == RoundPhase.answering && !hintAsked && hintSheetOpenedAtMs == null;
}

/// One played round, for the results list.
class RoundSummary {
  const RoundSummary({
    required this.number,
    required this.kind,
    required this.correctName,
    this.trackName = const DisplayName(),
    this.artistName = const DisplayName(),
    required this.chosenName,
    required this.correct,
    required this.points,
    required this.valid,
    required this.responseMs,
    this.correctEraId,
    this.chosenEraId,
  });

  final int number;
  final QuestionKind kind;

  /// The song or singer that was the answer. For an era question, the song that played.
  final DisplayName correctName;

  /// The song that played, for "Song · Singer" in the results list. For an artist question the
  /// answer ([correctName]) is the singer, so the list names the song from here.
  final DisplayName trackName;

  /// The song's singer, for "Song · Singer". Empty for an era question's song without a catalog name.
  final DisplayName artistName;

  /// Null when the window ran out.
  final DisplayName? chosenName;

  /// Era questions only: the era the song is from, and the era the player picked (null on a
  /// time-out). The screen names an era in the UI language.
  final int? correctEraId;
  final int? chosenEraId;
  final bool correct;
  final int points;
  final bool valid;
  final int responseMs;
}

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.config,
    required this.totalScore,
    required this.rounds,
    required this.skipped,
    required this.flagged,
    required this.bestBefore,
    required this.isNewBest,
    this.saveError,
  });

  /// The id the session was saved under. The server's score for it is looked up by this id.
  final String sessionId;
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

/// Why a session could not start or finish. The screen words it in the UI language.
enum SessionProblem {
  /// No songs are on the phone at all.
  noSongs,
  tooFewSongs,
  tooFewArtists,

  /// No songs for the picked era ([SessionError.generationId]).
  noSongsInEra,

  /// None of the session's [SessionError.count] clips could be played.
  clipsFailed,

  /// Anything else; [SessionError.detail] is the technical message.
  unexpected,
}

class SessionError {
  const SessionError(this.problem, {this.generationId, this.count, this.detail});

  final SessionProblem problem;
  final int? generationId;
  final int? count;
  final String? detail;
}

class SessionState {
  const SessionState({
    this.phase = SessionPhase.idle,
    this.config,
    this.round,
    this.summary,
    this.error,
    this.ad = RoundAd.none,
  });

  final SessionPhase phase;
  final SessionConfig? config;
  final RoundView? round;
  final SessionSummary? summary;
  final SessionError? error;

  /// A full-screen ad over the round: an interstitial between rounds, or the hint's rewarded ad.
  final RoundAd ad;

  static const idle = SessionState();
}
