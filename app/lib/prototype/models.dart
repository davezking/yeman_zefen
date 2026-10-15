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
  final PackProblem? problem;
  final int? shortfallMb;

  String name(Locale locale) => locale.languageCode == 'am' ? nameAm : nameEn;

  /// On the phone and playable: installed, or installed with an update waiting.
  bool get isOnPhone =>
      status == PackStatus.installed || status == PackStatus.updateAvailable;

  PackItem copyWith({
    PackStatus? status,
    double? progress,
    PackProblem? problem,
    int? shortfallMb,
    bool clearProgress = false,
    bool clearProblem = false,
  }) => PackItem(
    id: id,
    nameAm: nameAm,
    nameEn: nameEn,
    generationId: generationId,
    songCount: songCount,
    sizeMb: sizeMb,
    status: status ?? this.status,
    progress: clearProgress ? null : (progress ?? this.progress),
    updateSizeMb: updateSizeMb,
    problem: clearProblem ? null : (problem ?? this.problem),
    shortfallMb: shortfallMb ?? this.shortfallMb,
  );
}

/// How full the clip cache is: prefetched clips, evicted oldest first.
class CacheUsage {
  const CacheUsage({required this.usedMb, required this.capMb});

  final int usedMb;
  final int capMb;
}

/// What the phone is connected to, for the pack-download rules.
enum Connection { wifi, mobile, offline }
