// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Guess the Song';

  @override
  String get homeTagline => 'Listen to the clip and pick the song.';

  @override
  String get playButton => 'Play';

  @override
  String get appName => 'Yeman Zefen';

  @override
  String get appTagline => 'Whose song is it?';

  @override
  String get onboardLangTitle => 'Choose your language';

  @override
  String get onboardLangAmharic => 'አማርኛ';

  @override
  String get onboardLangEnglish => 'English';

  @override
  String get onboardLangLater => 'You can change this anytime in Settings.';

  @override
  String get onboardWelcomeTitle => 'Name the song from its first notes.';

  @override
  String get onboardWelcomeBody =>
      'Hear a short clip, then pick the song or the singer. No sign-up needed.';

  @override
  String get onboardWelcomeStart => 'Start playing';

  @override
  String get commonNext => 'Next';

  @override
  String get homeHello => 'Ready for a song?';

  @override
  String get homeQuickPlay => 'Play';

  @override
  String get homeQuickPlayLabel => 'Play button starts';

  @override
  String homeQuickPlaySettings(String era, String mode, String difficulty) {
    return '$era · $mode · $difficulty';
  }

  @override
  String get homeChooseMode => 'More ways to play';

  @override
  String get homeModeIntroShort => 'The opening of the song';

  @override
  String get homeModeMiddleShort => 'Harder · +25% points';

  @override
  String get homeModeEraShort => 'Name the generation';

  @override
  String get homeLeaderboard => 'Leaderboard';

  @override
  String get homeLeaderboardGuest => 'Sign in to get a rank';

  @override
  String get homeLeaderboardOffline => 'Needs internet';

  @override
  String get homeBestLabel => 'Your best';

  @override
  String get homeBestNone => 'Play a game to set your first best score.';

  @override
  String get homeBuiltIn => 'Built-in songs';

  @override
  String get homeQuickPlayModeIntro => 'Intro';

  @override
  String get homeQuickPlayModeMiddle => 'Middle';

  @override
  String get homeQuickPlayModeEra => 'Which Era?';

  @override
  String get difficultyEasyShort => 'Easy';

  @override
  String get difficultyMediumShort => 'Medium';

  @override
  String get difficultyHardShort => 'Hard';

  @override
  String get navHome => 'Home';

  @override
  String get navPlay => 'Play';

  @override
  String get navSettings => 'Settings';

  @override
  String get navBack => 'Back';

  @override
  String get modeTitle => 'How do you want to play?';

  @override
  String get modeIntroName => 'Guess the Intro';

  @override
  String get modeIntroDesc => 'The opening of the song. The classic.';

  @override
  String get modeMiddleName => 'Guess from the Middle';

  @override
  String get modeMiddleDesc =>
      'A clip from the middle. Harder, so it\'s worth more.';

  @override
  String get modeMiddleTag => '+25%';

  @override
  String get modeEraName => 'Which Era?';

  @override
  String get modeEraDesc => 'Hear a song and name its generation.';

  @override
  String get modeBonus => 'Bonus';

  @override
  String get modeGuessLabel => 'Guess the';

  @override
  String get modeGuessSong => 'Song';

  @override
  String get modeGuessArtist => 'Artist';

  @override
  String get eraTitle => 'Pick an era';

  @override
  String get eraAll => 'All eras';

  @override
  String get eraGolden => 'Golden Age';

  @override
  String get eraGoldenRange => 'Before 1980';

  @override
  String get era80s => 'The \'80s';

  @override
  String get era90s => 'The \'90s';

  @override
  String get era2000s => 'The 2000s';

  @override
  String get eraModern => 'Modern';

  @override
  String get eraModernRange => '2010 and later';

  @override
  String get eraOfflineUnavailable => 'Needs internet or a downloaded pack';

  @override
  String get genreTitle => 'Genre (optional)';

  @override
  String get genreAny => 'Any genre';

  @override
  String get genreTizita => 'Tizita';

  @override
  String get genreEthiojazz => 'Ethio-jazz';

  @override
  String get genreTraditional => 'Traditional';

  @override
  String get genrePop => 'Pop';

  @override
  String get genreHiphop => 'Hip-hop';

  @override
  String get difficultyTitle => 'Clip length';

  @override
  String get difficultyEasy => 'Easy · 10 s';

  @override
  String get difficultyMedium => 'Medium · 5 s';

  @override
  String get difficultyHard => 'Hard · 3 s';

  @override
  String setupStart(int total) {
    return 'Start · $total rounds';
  }

  @override
  String get setupTooFewSongs =>
      'Not enough songs for this choice yet. Try \"All eras\" or another genre.';

  @override
  String roundCounter(int n, int total) {
    return '$n / $total';
  }

  @override
  String roundScore(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '$pointsString pts';
  }

  @override
  String get roundLoading => 'Getting the next song…';

  @override
  String get roundLoadingNote =>
      'If it doesn\'t load in 10 seconds, we\'ll skip this round. You won\'t lose points.';

  @override
  String get roundListen => 'Listen…';

  @override
  String get roundQuestionSong => 'Which song is this?';

  @override
  String get roundQuestionArtist => 'Who sings this?';

  @override
  String get roundQuestionEra => 'Which era is this song from?';

  @override
  String roundSecondsLeft(int s) {
    return '$s s';
  }

  @override
  String get roundHint => 'Hint: remove 2 answers';

  @override
  String get roundHintTerms =>
      'Watch a short ad. This round\'s points are halved.';

  @override
  String get roundHintPaused =>
      'The timer pauses for up to 8 seconds while you decide, and while the ad plays.';

  @override
  String roundHintClosesIn(int s) {
    return '$s s';
  }

  @override
  String get roundTimerPaused => 'Paused';

  @override
  String get roundHintWatch => 'Watch ad';

  @override
  String get roundHintCancel => 'No thanks';

  @override
  String get roundHintButton => 'Hint';

  @override
  String get roundLeave => 'Leave game';

  @override
  String get roundLeaveTitle => 'Leave this game?';

  @override
  String get roundLeaveBody => 'Your score for this game won\'t be saved.';

  @override
  String get roundLeaveConfirm => 'Leave';

  @override
  String get roundLeaveCancel => 'Keep playing';

  @override
  String a11yAnswer(int n, String text) {
    return 'Answer $n: $text';
  }

  @override
  String a11yTimer(int s) {
    return '$s seconds left';
  }

  @override
  String get a11yPlaying => 'Clip playing';

  @override
  String get feedbackCorrect => 'Correct';

  @override
  String feedbackPoints(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '+$pointsString';
  }

  @override
  String feedbackSpeedBonus(int bonus) {
    return 'Speed bonus +$bonus';
  }

  @override
  String get feedbackWrong => 'Not this one';

  @override
  String feedbackReveal(String song, String artist) {
    return 'It was $song · $artist';
  }

  @override
  String feedbackTapToContinue(int s) {
    return 'Tap to continue · $s s';
  }

  @override
  String get feedbackYourPick => 'Your pick';

  @override
  String feedbackRevealEra(String era) {
    return 'It\'s from $era';
  }

  @override
  String get feedbackTimeout => 'Time\'s up';

  @override
  String get feedbackHintUsed => 'Hint used · half points';

  @override
  String get feedbackSkipped =>
      'We skipped a song that wouldn\'t load or play. No points lost.';

  @override
  String get resultsTitle => 'Game complete';

  @override
  String resultsScore(int score) {
    final intl.NumberFormat scoreNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String scoreString = scoreNumberFormat.format(score);

    return '$scoreString points';
  }

  @override
  String resultsCorrectCount(int correct, int total) {
    return '$correct of $total right';
  }

  @override
  String get resultsNewBest => 'New personal best';

  @override
  String get resultsRounds => 'Your rounds';

  @override
  String get resultsPlayAgain => 'Play again';

  @override
  String get resultsChange => 'Change era or mode';

  @override
  String get resultsHome => 'Home';

  @override
  String get resultsGuestRank => 'Sign in to put this score on the leaderboard';

  @override
  String resultsWeeklyRank(int rank) {
    return 'You\'re #$rank this week';
  }

  @override
  String get resultsSavedOffline =>
      'Score saved. It will be sent when you\'re back online.';

  @override
  String get resultsNotRanked =>
      'This game couldn\'t be checked, so it won\'t count toward rankings.';

  @override
  String get lbTitle => 'Leaderboard';

  @override
  String get lbWeekly => 'This week';

  @override
  String get lbAllTime => 'All time';

  @override
  String lbEra(String era) {
    return 'Era: $era';
  }

  @override
  String get lbYou => 'You';

  @override
  String lbYourRank(int rank) {
    return 'Your rank: #$rank';
  }

  @override
  String lbPoints(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '$pointsString pts';
  }

  @override
  String get lbNotRanked => 'Finish a game this week to get a rank.';

  @override
  String get lbGuestTitle => 'Want your name up here?';

  @override
  String get lbGuestBody => 'Sign in to rank. Your scores come with you.';

  @override
  String get lbGuestCta => 'Sign in';

  @override
  String get lbEmpty => 'No scores yet this week. Be the first.';

  @override
  String lbOffline(String time) {
    return 'You\'re offline. Showing the board from $time.';
  }

  @override
  String get lbOfflineNone => 'Connect to the internet to see the leaderboard.';

  @override
  String get lbLoading => 'Loading the leaderboard…';

  @override
  String get packsTitle => 'Offline play';

  @override
  String get packsIntro =>
      'Online, songs load as you play. Download packs to play without internet.';

  @override
  String get packsWifiOnly => 'Download packs on Wi-Fi only';

  @override
  String get packsMobilePrefetch => 'Download upcoming songs on mobile data';

  @override
  String get packsMobilePrefetchHelp =>
      'Off saves data: only songs already on your phone play.';

  @override
  String packsCache(int size) {
    return 'Cache $size MB';
  }

  @override
  String get packsClearCache => 'Clear cache';

  @override
  String get packsBuiltIn => 'Built-in songs';

  @override
  String packsBuiltInMeta(int count) {
    return '$count songs · comes with the app';
  }

  @override
  String get packsAlways => 'Always there';

  @override
  String get packsOnPhone => 'On this phone';

  @override
  String get packsAvailable => 'Available to download';

  @override
  String packsSongs(int count) {
    return '$count songs';
  }

  @override
  String packsSize(int size) {
    return '$size MB';
  }

  @override
  String get packsDownload => 'Download';

  @override
  String packsProgress(int percent) {
    return '$percent%';
  }

  @override
  String get packsCancel => 'Cancel';

  @override
  String get packsVerifying => 'Checking files…';

  @override
  String get packsDownloaded => 'Downloaded';

  @override
  String get packsUpdateAvailable => 'Update available';

  @override
  String packsUpdate(int size) {
    return 'Update · $size MB';
  }

  @override
  String get packsRemove => 'Remove';

  @override
  String packsRemoveConfirm(String name) {
    return 'Remove $name? You can download it again later.';
  }

  @override
  String get packsMobileDataTitle => 'Download on mobile data?';

  @override
  String packsMobileDataBody(int size) {
    return 'This pack is $size MB.';
  }

  @override
  String get packsMobileDataConfirm => 'Download now';

  @override
  String get packsMobileDataWait => 'Wait for Wi-Fi';

  @override
  String packsStorageFull(int size) {
    return 'Not enough space. Free up $size MB and try again.';
  }

  @override
  String get packsOffline => 'Connect to the internet to download packs.';

  @override
  String get authPromptTitle => 'Keep your scores';

  @override
  String get authPromptBody =>
      'Sign in to keep your progress on any phone and join the global leaderboard.';

  @override
  String get authPromptCarryOver => 'Your scores so far come with you.';

  @override
  String get authGoogle => 'Continue with Google';

  @override
  String get authApple => 'Continue with Apple';

  @override
  String get authEmail => 'Continue with email';

  @override
  String get authNotNow => 'Not now';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authEmailSubmit => 'Sign in';

  @override
  String get authEmailCreate => 'New here? Create an account';

  @override
  String get authEmailForgot => 'Forgot password?';

  @override
  String get authSigningIn => 'Signing in…';

  @override
  String authSignedIn(String name) {
    return 'Signed in as $name';
  }

  @override
  String get authLinkFailed =>
      'We couldn\'t link your account. Your scores are safe on this phone, and we\'ll try again.';

  @override
  String get authErrorEmail => 'Check your email address.';

  @override
  String get authErrorPassword => 'Wrong email or password.';

  @override
  String get authNameTitle => 'Pick a display name';

  @override
  String get authNameBody =>
      'This is the name other players see on the leaderboard.';

  @override
  String get authNameLabel => 'Display name';

  @override
  String get authNameSave => 'Save name';

  @override
  String get authNameErrorShort => 'Use at least 2 characters.';

  @override
  String get authNameErrorTaken => 'That name is taken. Try another.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsSound => 'Sound effects';

  @override
  String get settingsHaptics => 'Vibration';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsGuest => 'Playing as a guest';

  @override
  String get settingsSignIn => 'Sign in';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOutConfirm =>
      'Sign out? Your scores stay saved to your account.';

  @override
  String get settingsDelete => 'Delete account';

  @override
  String get settingsDeleteBody =>
      'This permanently deletes your account and your leaderboard scores. It can\'t be undone.';

  @override
  String get settingsDeleteConfirm => 'Delete my account';

  @override
  String get settingsAdPrivacy => 'Ad privacy choices';

  @override
  String settingsOffline(int count, int size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count packs',
      one: '1 pack',
    );
    return 'Offline play · $_temp0 · $size MB';
  }

  @override
  String get settingsPrivacy => 'Privacy policy';

  @override
  String get settingsAbout => 'About and licenses';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsMusicCredit =>
      'Music used under license from [ASSOCIATION NAME].';

  @override
  String get consentTitle => 'Ads keep this game free';

  @override
  String get consentBody =>
      'Next, you\'ll choose how ads may use your data. You can change this anytime in Settings.';

  @override
  String get consentContinue => 'Continue';

  @override
  String get adLabel => 'Ad';

  @override
  String get adLoading => 'Loading ad…';

  @override
  String get adUnavailable => 'No ad is available right now. Try again later.';

  @override
  String get adNotFinished => 'Watch the whole ad to get the hint.';

  @override
  String get adRewardCaption => 'Your hint is on its way…';

  @override
  String get adInterstitialCaption => 'Ads keep this game free';

  @override
  String get updateTitle => 'Time to update';

  @override
  String get updateBody =>
      'This version can\'t connect to the game server anymore. Update to use the leaderboard and get new songs.';

  @override
  String get updateCtaAndroid => 'Update on Google Play';

  @override
  String get updateCtaIos => 'Update on the App Store';

  @override
  String get updatePlayOffline => 'Play offline songs';

  @override
  String get offlineBanner =>
      'You\'re offline. You can still play built-in and downloaded songs.';

  @override
  String offlineBannerBuiltInOnly(int count) {
    return 'You\'re offline. You can still play the $count built-in songs.';
  }

  @override
  String get offlineBannerShort => 'You\'re offline.';

  @override
  String offlinePending(int count) {
    return '$count games waiting to be sent';
  }

  @override
  String get offlineSynced => 'Back online. Your scores have been sent.';

  @override
  String get emptyOutOfSongsTitle => 'You\'ve played every song here';

  @override
  String get emptyOutOfSongsBody =>
      'You\'re offline, and you\'ve heard all the songs on this phone recently. Download a pack in Settings › Offline play for more.';

  @override
  String get emptyOutOfSongsPacks => 'Browse packs';

  @override
  String get emptyOutOfSongsReplay => 'Play them again';

  @override
  String get errorGenericTitle => 'Something went wrong';

  @override
  String get errorGenericBody =>
      'Please try again. If it keeps happening, restart the app.';

  @override
  String get errorRetry => 'Try again';

  @override
  String get errorDownload =>
      'Download failed. Check your connection and try again.';

  @override
  String get errorPackCorrupt =>
      'Part of this pack didn\'t download correctly. Downloading it again…';

  @override
  String get errorSync =>
      'Couldn\'t send your scores. We\'ll try again automatically.';

  @override
  String get loadingApp => 'Tuning up…';

  @override
  String get loadingGeneric => 'Loading…';
}
