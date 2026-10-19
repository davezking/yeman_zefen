import 'dart:ui';

import '../core/widgets/pack_card.dart' show PackStatus;

export '../core/widgets/pack_card.dart' show PackStatus;

/// Plain data the prototype screens take. Nothing here knows about providers,
/// the database or the network: Phase 4 builds these from the real services and
/// hands them to the same screens.

/// The three ways to play (`docs/design/screens.md`, "Mode select").
enum GameMode { intro, middle, era }

/// What the player is asked to name in Intro and Middle: the song or the singer.
enum GuessTarget { song, artist }

/// Clip length: 10, 5 or 3 seconds.
enum Difficulty { easy, medium, hard }

/// The genres offered on era setup. [any] is the default, no filter.
enum Genre { any, tizita, ethiojazz, traditional, pop, hiphop }

/// Era ids as in the catalog's `generations` table; 0 is "All eras".
abstract final class EraId {
  static const all = 0;
  static const golden = 1;
  static const eighties = 2;
  static const nineties = 3;
  static const twoThousands = 4;
  static const modern = 5;

  /// In the order the cards are shown.
  static const ordered = [
    all,
    golden,
    eighties,
    nineties,
    twoThousands,
    modern,
  ];
}

/// What the Play button starts: the last-used era, mode and difficulty.
class PlaySettings {
  const PlaySettings({
    this.generationId = EraId.all,
    this.mode = GameMode.intro,
    this.guess = GuessTarget.song,
    this.genre = Genre.any,
    this.difficulty = Difficulty.easy,
  });

  final int generationId;
  final GameMode mode;
  final GuessTarget guess;
  final Genre genre;
  final Difficulty difficulty;

  PlaySettings copyWith({
    int? generationId,
    GameMode? mode,
    GuessTarget? guess,
    Genre? genre,
    Difficulty? difficulty,
  }) => PlaySettings(
    generationId: generationId ?? this.generationId,
    mode: mode ?? this.mode,
    guess: guess ?? this.guess,
    genre: genre ?? this.genre,
    difficulty: difficulty ?? this.difficulty,
  );
}

/// The player: a guest, or signed in with a name.
class UserInfo {
  const UserInfo.guest({this.bestScore})
    : displayName = null,
      weeklyRank = null;

  const UserInfo.signedIn({
    required String this.displayName,
    this.bestScore,
    this.weeklyRank,
  });

  /// Null for a guest.
  final String? displayName;

  /// Null before the first finished game.
  final int? bestScore;

  /// This week's leaderboard rank; null for a guest or before a ranked game.
  final int? weeklyRank;

  bool get isGuest => displayName == null;
}

/// A song in the catalog, as the app shows it. Names are stored per script
/// (`title_am`/`title_latin`, `name_am`/`name_en`): the Amharic field in
/// Amharic, the Latin one in English, never transliterated at runtime.
class Track {
  const Track({
    required this.id,
    required this.titleAm,
    required this.titleLatin,
    required this.artistAm,
    required this.artistLatin,
    required this.generationId,
    required this.genre,
  });

  final String id;
  final String titleAm;
  final String titleLatin;
  final String artistAm;
  final String artistLatin;
  final int generationId;
  final Genre genre;

  String title(Locale locale) =>
      locale.languageCode == 'am' ? titleAm : titleLatin;
  String artist(Locale locale) =>
      locale.languageCode == 'am' ? artistAm : artistLatin;
}

/// Why a pack row is in the [PackStatus.failed] state.
enum PackProblem {
  /// The download failed: "Check your connection and try again", with Try again.
  downloadFailed,

  /// A file did not match its checksum. The app retries by itself: no button.
  corrupt,

  /// Not enough free space; [PackItem.shortfallMb] more is needed.
  storageFull,
}

/// A song pack in Settings › Offline play.
class PackItem {
  const PackItem({
    required this.id,
    required this.nameAm,
    required this.nameEn,
    required this.generationId,
    required this.songCount,
    required this.sizeMb,
    this.status = PackStatus.notInstalled,
    this.progress,
    this.updateSizeMb,
    this.updating = false,
    this.problem,
    this.shortfallMb,
  });

  final String id;
  final String nameAm;
  final String nameEn;
  final int generationId;
  final int songCount;

  /// Download size in MB.
  final int sizeMb;
  final PackStatus status;

  /// 0 to 1 while downloading.
  final double? progress;

  /// For [PackStatus.updateAvailable]: the size of the update in MB.
  final int? updateSizeMb;

  /// The download under way (or failed) is an update: the installed version
  /// stays on the phone and playable until the new one is in.
  final bool updating;
  final PackProblem? problem;
  final int? shortfallMb;

  String name(Locale locale) => locale.languageCode == 'am' ? nameAm : nameEn;

  /// On the phone and playable: installed, with an update waiting, or being updated.
  bool get isOnPhone =>
      status == PackStatus.installed ||
      status == PackStatus.updateAvailable ||
      updating;

  /// What the next download costs: the update, or the whole pack.
  int get downloadSizeMb => (status == PackStatus.updateAvailable || updating)
      ? (updateSizeMb ?? sizeMb)
      : sizeMb;

  PackItem copyWith({
    PackStatus? status,
    double? progress,
    bool? updating,
    PackProblem? problem,
    int? shortfallMb,
    bool clearProgress = false,
    bool clearProblem = false,
    bool clearUpdate = false,
  }) => PackItem(
    id: id,
    nameAm: nameAm,
    nameEn: nameEn,
    generationId: generationId,
    songCount: songCount,
    sizeMb: sizeMb,
    status: status ?? this.status,
    progress: clearProgress ? null : (progress ?? this.progress),
    updateSizeMb: clearUpdate ? null : updateSizeMb,
    updating: clearUpdate ? false : (updating ?? this.updating),
    problem: clearProblem ? null : (problem ?? this.problem),
    shortfallMb: clearProblem ? null : (shortfallMb ?? this.shortfallMb),
  );
}

/// How full the clip cache is (prefetched clips, evicted oldest first), and
/// what the built-in songs and the downloaded packs take besides.
class CacheUsage {
  const CacheUsage({
    required this.usedMb,
    required this.capMb,
    this.builtInMb = 0,
    this.packsMb = 0,
  });

  final int usedMb;
  final int capMb;
  final int builtInMb;
  final int packsMb;
}

/// What the phone is connected to, for the pack-download rules.
enum Connection { wifi, mobile, offline }

// ---------------------------------------------------------------------------
// The round

/// What a round asks: the song, the singer, or the era (Which Era? mode).
enum QuestionKind { song, artist, era }

/// Where a round is. The reveal states carry an icon and a word as well as color.
enum RoundPhase {
  /// Rare: the round's clip is still downloading (a slow connection, an era
  /// with no songs on the phone). Up to 10 s, then the round is skipped.
  loading,

  /// The clip plays and the timer runs; the player can answer.
  answering,

  /// The player picked the right one.
  correct,

  /// The player picked a wrong one; the right one is shown.
  wrong,

  /// The window ran out with no pick; the right one is shown.
  timeout,
}

/// What covers the round screen, if anything. The timer is stopped under
/// every one of these.
enum RoundOverlay {
  none,

  /// "Hint: remove 2 answers", closing itself after 8 s.
  hintSheet,

  /// The rewarded ad behind the hint.
  rewardedAd,

  /// The mandatory ad between rounds.
  interstitial,

  /// "Leave this game?"
  leaveDialog,

  /// The app came back from the background, or a call took the audio: the clip plays again
  /// when the player resumes, and the time already used still counts.
  paused,
}

/// One of the four answers: a track (its song or its singer is the text) or,
/// in Which Era?, an era.
class RoundOption {
  const RoundOption.track(Track this.track) : generationId = null;
  const RoundOption.era(int this.generationId) : track = null;

  final Track? track;
  final int? generationId;
}

/// Everything the round screen shows at one moment. The simulation (and in
/// Phase 4 the real engine) builds a new one whenever anything changes.
class RoundView {
  const RoundView({
    required this.roundNumber,
    required this.totalRounds,
    required this.score,
    required this.eraFilterId,
    required this.difficulty,
    required this.kind,
    required this.options,
    required this.correctIndex,
    required this.track,
    required this.phase,
    required this.clipPlaying,
    required this.timeFraction,
    required this.secondsLeft,
    this.timerPaused = false,
    this.pickedIndex,
    this.removed = const {},
    this.hintAvailable = false,
    this.hintUsed = false,
    this.points = 0,
    this.speedBonus = 0,
    this.valid = true,
    this.feedbackSecondsLeft = 0,
    this.overlay = RoundOverlay.none,
    this.overlaySeconds = 0,
  });

  /// 1-based, for "4 / 10".
  final int roundNumber;
  final int totalRounds;

  /// The running score, including the round just answered.
  final int score;

  /// The era chip: the session's era, 0 for all.
  final int eraFilterId;
  final Difficulty difficulty;
  final QuestionKind kind;
  final List<RoundOption> options;
  final int correctIndex;

  /// The round's song, for "It was Song · Artist".
  final Track track;
  final RoundPhase phase;

  /// The reels turn while the clip plays.
  final bool clipPlaying;

  /// What is left of the answer window, 1 down to 0.
  final double timeFraction;
  final int secondsLeft;

  /// The timer is stopped (hint sheet, ad, leave dialog, app in the background):
  /// the pill reads "Paused".
  final bool timerPaused;
  final int? pickedIndex;

  /// Answers the hint took away: faded and not tappable.
  final Set<int> removed;
  final bool hintAvailable;
  final bool hintUsed;

  /// Points for this round, once answered.
  final int points;
  final int speedBonus;

  /// False when the answer was faster than a person can react (under 200 ms): it scores 0 and the
  /// screen says it does not count, instead of "Correct".
  final bool valid;

  /// The "Tap to continue · 5 s" countdown, in the wrong and time-out states.
  final int feedbackSecondsLeft;
  final RoundOverlay overlay;

  /// The seconds left on the hint sheet or the ad.
  final int overlaySeconds;

  bool get revealed =>
      phase != RoundPhase.answering && phase != RoundPhase.loading;
}

/// How one round went, for the results list.
class RoundResult {
  const RoundResult({
    required this.track,
    required this.correct,
    required this.points,
    this.hintUsed = false,
    this.timedOut = false,
    this.number,
  });

  /// The round's number as played (a skipped round leaves a gap); null
  /// numbers the rows in order.
  final int? number;
  final Track track;
  final bool correct;
  final int points;
  final bool hintUsed;
  final bool timedOut;
}

// ---------------------------------------------------------------------------
// Results

/// Whether the score on Results is still the phone's own count.
enum ScoreSync {
  /// Counted on the phone; the server's answer is awaited.
  provisional,

  /// The server's score, which replaced the provisional one.
  synced,

  /// No connection: the game is queued and will be sent later.
  savedOffline,

  /// The server could not check the game, so it does not count for rankings.
  rejected,
}

class ResultsView {
  const ResultsView({
    required this.score,
    required this.rounds,
    required this.user,
    this.newBest = false,
    this.sync = ScoreSync.provisional,
  });

  final int score;
  final List<RoundResult> rounds;
  final UserInfo user;
  final bool newBest;
  final ScoreSync sync;

  int get correctCount => rounds.where((r) => r.correct).length;
}

// ---------------------------------------------------------------------------
// Leaderboard

enum LeaderboardScope { weekly, allTime }

/// What the board has to show.
enum LeaderboardState {
  ready,

  /// Still loading: a skeleton, after a short delay.
  loading,

  /// Nobody has a score yet.
  empty,

  /// No connection; an earlier copy of the board is shown, with its time.
  offlineCached,

  /// No connection and nothing saved.
  offlineNone,
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.points,
    this.colorIndex = 0,
  });

  final int rank;
  final String name;
  final int points;

  /// Picks the avatar tile's color.
  final int colorIndex;
}

class LeaderboardView {
  const LeaderboardView({
    required this.scope,
    required this.generationId,
    required this.entries,
    required this.user,
    this.me,
    this.state = LeaderboardState.ready,
    this.cachedAt,
  });

  final LeaderboardScope scope;

  /// The era filter; 0 for all eras.
  final int generationId;

  /// Everyone ranked, best first.
  final List<LeaderboardEntry> entries;
  final UserInfo user;

  /// The signed-in player's own row (null: not ranked this week).
  final LeaderboardEntry? me;
  final LeaderboardState state;

  /// "3:20 PM", when [state] is [LeaderboardState.offlineCached].
  final String? cachedAt;
}

// ---------------------------------------------------------------------------
// Sign in

enum SignInProvider { apple, google, email }

/// The sign-in sheet's progress.
enum SignInStatus {
  idle,

  /// Waiting on the provider: the buttons are off, the pressed one spins.
  signingIn,

  /// Signed in, but the scores could not be attached to the account yet.
  linkFailed,
}

enum EmailError { none, email, password }

enum NameError {
  none,
  tooShort,
  taken,

  /// The save did not go through for a reason that is not the name's length (offline, a server
  /// error, a name the server refused).
  failed,
}
