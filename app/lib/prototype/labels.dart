import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../l10n/app_localizations.dart';
import 'models.dart';

/// Turns the prototype's enums into the words on screen, from the ARB strings.
/// Era and genre names also exist in the catalog (admin-editable); until the
/// app reads them from there, these are the same words.
extension PrototypeLabels on AppLocalizations {
  String eraLabel(int generationId) => switch (generationId) {
    EraId.golden => eraGolden,
    EraId.eighties => era80s,
    EraId.nineties => era90s,
    EraId.twoThousands => era2000s,
    EraId.modern => eraModern,
    _ => eraAll,
  };

  /// The years under an era's name, for the two eras that have them.
  String? eraRange(int generationId) => switch (generationId) {
    EraId.golden => eraGoldenRange,
    EraId.modern => eraModernRange,
    _ => null,
  };

  String modeName(GameMode mode) => switch (mode) {
    GameMode.intro => modeIntroName,
    GameMode.middle => modeMiddleName,
    GameMode.era => modeEraName,
  };

  String modeDescription(GameMode mode) => switch (mode) {
    GameMode.intro => modeIntroDesc,
    GameMode.middle => modeMiddleDesc,
    GameMode.era => modeEraDesc,
  };

  /// The line under a mode's name on Home.
  String modeHomeShort(GameMode mode) => switch (mode) {
    GameMode.intro => homeModeIntroShort,
    GameMode.middle => homeModeMiddleShort,
    GameMode.era => homeModeEraShort,
  };

  /// The word for a mode in the "Play button starts" line.
  String modeQuickPlay(GameMode mode) => switch (mode) {
    GameMode.intro => homeQuickPlayModeIntro,
    GameMode.middle => homeQuickPlayModeMiddle,
    GameMode.era => homeQuickPlayModeEra,
  };

  String? modeTag(GameMode mode) => switch (mode) {
    GameMode.intro => null,
    GameMode.middle => modeMiddleTag,
    GameMode.era => modeBonus,
  };

  String difficultyLabel(Difficulty d) => switch (d) {
    Difficulty.easy => difficultyEasy,
    Difficulty.medium => difficultyMedium,
    Difficulty.hard => difficultyHard,
  };

  String difficultyQuickPlay(Difficulty d) => switch (d) {
    Difficulty.easy => difficultyEasyShort,
    Difficulty.medium => difficultyMediumShort,
    Difficulty.hard => difficultyHardShort,
  };

  String genreLabel(Genre g) => switch (g) {
    Genre.any => genreAny,
    Genre.tizita => genreTizita,
    Genre.ethiojazz => genreEthiojazz,
    Genre.traditional => genreTraditional,
    Genre.pop => genrePop,
    Genre.hiphop => genreHiphop,
  };

  String guessLabel(GuessTarget t) => switch (t) {
    GuessTarget.song => modeGuessSong,
    GuessTarget.artist => modeGuessArtist,
  };

  /// "The '80s · Intro · Easy", the line under "Play button starts".
  String quickPlaySummary(PlaySettings s) => homeQuickPlaySettings(
    eraLabel(s.generationId),
    modeQuickPlay(s.mode),
    difficultyQuickPlay(s.difficulty),
  );

  /// The same line when the phone is offline: the built-in songs, whatever the era.
  String quickPlaySummaryOffline(PlaySettings s) => homeQuickPlaySettings(
    homeBuiltIn,
    modeQuickPlay(s.mode),
    difficultyQuickPlay(s.difficulty),
  );
}

/// The icon on a mode's row and card.
IconData modeIcon(GameMode mode) => switch (mode) {
  GameMode.intro => Icons.music_note_rounded,
  GameMode.middle => Icons.show_chart_rounded,
  GameMode.era => Icons.schedule_rounded,
};

/// The fill behind a mode's icon: yellow, coral, sage.
Color modeColor(GameMode mode) => switch (mode) {
  GameMode.intro => ColorTokens.paletteSun400,
  GameMode.middle => ColorTokens.paletteCoral,
  GameMode.era => ColorTokens.paletteSage,
};
