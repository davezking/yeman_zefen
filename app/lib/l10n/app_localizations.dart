import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_am.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('am'),
    Locale('en'),
  ];

  /// App name shown in the task switcher and on the home screen
  ///
  /// In en, this message translates to:
  /// **'Guess the Song'**
  String get appTitle;

  /// No description provided for @homeTagline.
  ///
  /// In en, this message translates to:
  /// **'Listen to the clip and pick the song.'**
  String get homeTagline;

  /// No description provided for @playButton.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playButton;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Yeman Zefen'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Whose song is it?'**
  String get appTagline;

  /// No description provided for @onboardLangTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get onboardLangTitle;

  /// No description provided for @onboardLangAmharic.
  ///
  /// In en, this message translates to:
  /// **'አማርኛ'**
  String get onboardLangAmharic;

  /// No description provided for @onboardLangEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get onboardLangEnglish;

  /// No description provided for @onboardLangLater.
  ///
  /// In en, this message translates to:
  /// **'You can change this anytime in Settings.'**
  String get onboardLangLater;

  /// No description provided for @onboardWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Name the song from its first notes.'**
  String get onboardWelcomeTitle;

  /// No description provided for @onboardWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Hear a short clip, then pick the song or the singer. No sign-up needed.'**
  String get onboardWelcomeBody;

  /// No description provided for @onboardWelcomeStart.
  ///
  /// In en, this message translates to:
  /// **'Start playing'**
  String get onboardWelcomeStart;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @homeHello.
  ///
  /// In en, this message translates to:
  /// **'Ready for a song?'**
  String get homeHello;

  /// No description provided for @homeQuickPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get homeQuickPlay;

  /// No description provided for @homeQuickPlayLabel.
  ///
  /// In en, this message translates to:
  /// **'Play button starts'**
  String get homeQuickPlayLabel;

  /// No description provided for @homeQuickPlaySettings.
  ///
  /// In en, this message translates to:
  /// **'{era} · {mode} · {difficulty}'**
  String homeQuickPlaySettings(String era, String mode, String difficulty);

  /// No description provided for @homeChooseMode.
  ///
  /// In en, this message translates to:
  /// **'More ways to play'**
  String get homeChooseMode;

  /// No description provided for @homeModeIntroShort.
  ///
  /// In en, this message translates to:
  /// **'The opening of the song'**
  String get homeModeIntroShort;

  /// No description provided for @homeModeMiddleShort.
  ///
  /// In en, this message translates to:
  /// **'Harder · +25% points'**
  String get homeModeMiddleShort;

  /// No description provided for @homeModeEraShort.
  ///
  /// In en, this message translates to:
  /// **'Name the generation'**
  String get homeModeEraShort;

  /// No description provided for @homeLeaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get homeLeaderboard;

  /// No description provided for @homeLeaderboardGuest.
  ///
  /// In en, this message translates to:
  /// **'Sign in to get a rank'**
  String get homeLeaderboardGuest;

  /// No description provided for @homeLeaderboardOffline.
  ///
  /// In en, this message translates to:
  /// **'Needs internet'**
  String get homeLeaderboardOffline;

  /// No description provided for @homeBestLabel.
  ///
  /// In en, this message translates to:
  /// **'Your best'**
  String get homeBestLabel;

  /// No description provided for @homeBestNone.
  ///
  /// In en, this message translates to:
  /// **'Play a game to set your first best score.'**
  String get homeBestNone;

  /// No description provided for @homeBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in songs'**
  String get homeBuiltIn;

  /// No description provided for @homeQuickPlayModeIntro.
  ///
  /// In en, this message translates to:
  /// **'Intro'**
  String get homeQuickPlayModeIntro;

  /// No description provided for @homeQuickPlayModeMiddle.
  ///
  /// In en, this message translates to:
  /// **'Middle'**
  String get homeQuickPlayModeMiddle;

  /// No description provided for @homeQuickPlayModeEra.
  ///
  /// In en, this message translates to:
  /// **'Which Era?'**
  String get homeQuickPlayModeEra;

  /// No description provided for @difficultyEasyShort.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasyShort;

  /// No description provided for @difficultyMediumShort.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get difficultyMediumShort;

  /// No description provided for @difficultyHardShort.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get difficultyHardShort;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get navPlay;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get navBack;

  /// No description provided for @modeTitle.
  ///
  /// In en, this message translates to:
  /// **'How do you want to play?'**
  String get modeTitle;

  /// No description provided for @modeIntroName.
  ///
  /// In en, this message translates to:
  /// **'Guess the Intro'**
  String get modeIntroName;

  /// No description provided for @modeIntroDesc.
  ///
  /// In en, this message translates to:
  /// **'The opening of the song. The classic.'**
  String get modeIntroDesc;

  /// No description provided for @modeMiddleName.
  ///
  /// In en, this message translates to:
  /// **'Guess from the Middle'**
  String get modeMiddleName;

  /// No description provided for @modeMiddleDesc.
  ///
  /// In en, this message translates to:
  /// **'A clip from the middle. Harder, so it\'s worth more.'**
  String get modeMiddleDesc;

  /// No description provided for @modeMiddleTag.
  ///
  /// In en, this message translates to:
  /// **'+25%'**
  String get modeMiddleTag;

  /// No description provided for @modeEraName.
  ///
  /// In en, this message translates to:
  /// **'Which Era?'**
  String get modeEraName;

  /// No description provided for @modeEraDesc.
  ///
  /// In en, this message translates to:
  /// **'Hear a song and name its generation.'**
  String get modeEraDesc;

  /// No description provided for @modeBonus.
  ///
  /// In en, this message translates to:
  /// **'Bonus'**
  String get modeBonus;

  /// No description provided for @modeGuessLabel.
  ///
  /// In en, this message translates to:
  /// **'Guess the'**
  String get modeGuessLabel;

  /// No description provided for @modeGuessSong.
  ///
  /// In en, this message translates to:
  /// **'Song'**
  String get modeGuessSong;

  /// No description provided for @modeGuessArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get modeGuessArtist;

  /// No description provided for @eraTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick an era'**
  String get eraTitle;

  /// No description provided for @eraAll.
  ///
  /// In en, this message translates to:
  /// **'All eras'**
  String get eraAll;

  /// No description provided for @eraGolden.
  ///
  /// In en, this message translates to:
  /// **'Golden Age'**
  String get eraGolden;

  /// No description provided for @eraGoldenRange.
  ///
  /// In en, this message translates to:
  /// **'Before 1980'**
  String get eraGoldenRange;

  /// No description provided for @era80s.
  ///
  /// In en, this message translates to:
  /// **'The \'80s'**
  String get era80s;

  /// No description provided for @era90s.
  ///
  /// In en, this message translates to:
  /// **'The \'90s'**
  String get era90s;

  /// No description provided for @era2000s.
  ///
  /// In en, this message translates to:
  /// **'The 2000s'**
  String get era2000s;

  /// No description provided for @eraModern.
  ///
  /// In en, this message translates to:
  /// **'Modern'**
  String get eraModern;

  /// No description provided for @eraModernRange.
  ///
  /// In en, this message translates to:
  /// **'2010 and later'**
  String get eraModernRange;

  /// No description provided for @eraOfflineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Needs internet or a downloaded pack'**
  String get eraOfflineUnavailable;

  /// No description provided for @genreTitle.
  ///
  /// In en, this message translates to:
  /// **'Genre (optional)'**
  String get genreTitle;

  /// No description provided for @genreAny.
  ///
  /// In en, this message translates to:
  /// **'Any genre'**
  String get genreAny;

  /// No description provided for @genreTizita.
  ///
  /// In en, this message translates to:
  /// **'Tizita'**
  String get genreTizita;

  /// No description provided for @genreEthiojazz.
  ///
  /// In en, this message translates to:
  /// **'Ethio-jazz'**
  String get genreEthiojazz;

  /// No description provided for @genreTraditional.
  ///
  /// In en, this message translates to:
  /// **'Traditional'**
  String get genreTraditional;

  /// No description provided for @genrePop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get genrePop;

  /// No description provided for @genreHiphop.
  ///
  /// In en, this message translates to:
  /// **'Hip-hop'**
  String get genreHiphop;

  /// No description provided for @difficultyTitle.
  ///
  /// In en, this message translates to:
  /// **'Clip length'**
  String get difficultyTitle;

  /// No description provided for @difficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy · 10 s'**
  String get difficultyEasy;

  /// No description provided for @difficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium · 5 s'**
  String get difficultyMedium;

  /// No description provided for @difficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard · 3 s'**
  String get difficultyHard;

  /// No description provided for @setupStart.
  ///
  /// In en, this message translates to:
  /// **'Start · {total} rounds'**
  String setupStart(int total);

  /// No description provided for @setupTooFewSongs.
  ///
  /// In en, this message translates to:
  /// **'Not enough songs for this choice yet. Try \"All eras\" or another genre.'**
  String get setupTooFewSongs;

  /// No description provided for @roundCounter.
  ///
  /// In en, this message translates to:
  /// **'{n} / {total}'**
  String roundCounter(int n, int total);

  /// No description provided for @roundScore.
  ///
  /// In en, this message translates to:
  /// **'{points} pts'**
  String roundScore(int points);

  /// No description provided for @roundLoading.
  ///
  /// In en, this message translates to:
  /// **'Getting the next song…'**
  String get roundLoading;

  /// No description provided for @roundLoadingNote.
  ///
  /// In en, this message translates to:
  /// **'If it doesn\'t load in 10 seconds, we\'ll skip this round. You won\'t lose points.'**
  String get roundLoadingNote;

  /// No description provided for @roundListen.
  ///
  /// In en, this message translates to:
  /// **'Listen…'**
  String get roundListen;

  /// No description provided for @roundQuestionSong.
  ///
  /// In en, this message translates to:
  /// **'Which song is this?'**
  String get roundQuestionSong;

  /// No description provided for @roundQuestionArtist.
  ///
  /// In en, this message translates to:
  /// **'Who sings this?'**
  String get roundQuestionArtist;

  /// No description provided for @roundQuestionEra.
  ///
  /// In en, this message translates to:
  /// **'Which era is this song from?'**
  String get roundQuestionEra;

  /// No description provided for @roundSecondsLeft.
  ///
  /// In en, this message translates to:
  /// **'{s} s'**
  String roundSecondsLeft(int s);

  /// No description provided for @roundHint.
  ///
  /// In en, this message translates to:
  /// **'Hint: remove 2 answers'**
  String get roundHint;

  /// No description provided for @roundHintTerms.
  ///
  /// In en, this message translates to:
  /// **'Watch a short ad. This round\'s points are halved.'**
  String get roundHintTerms;

  /// No description provided for @roundHintPaused.
  ///
  /// In en, this message translates to:
  /// **'The timer pauses for up to 8 seconds while you decide, and while the ad plays.'**
  String get roundHintPaused;

  /// No description provided for @roundHintClosesIn.
  ///
  /// In en, this message translates to:
  /// **'{s} s'**
  String roundHintClosesIn(int s);

  /// No description provided for @roundTimerPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get roundTimerPaused;

  /// No description provided for @roundHintWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch ad'**
  String get roundHintWatch;

  /// No description provided for @roundHintCancel.
  ///
  /// In en, this message translates to:
  /// **'No thanks'**
  String get roundHintCancel;

  /// No description provided for @roundHintButton.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get roundHintButton;

  /// No description provided for @roundLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave game'**
  String get roundLeave;

  /// No description provided for @roundLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave this game?'**
  String get roundLeaveTitle;

  /// No description provided for @roundLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'Your score for this game won\'t be saved.'**
  String get roundLeaveBody;

  /// No description provided for @roundLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get roundLeaveConfirm;

  /// No description provided for @roundLeaveCancel.
  ///
  /// In en, this message translates to:
  /// **'Keep playing'**
  String get roundLeaveCancel;

  /// No description provided for @a11yAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer {n}: {text}'**
  String a11yAnswer(int n, String text);

  /// No description provided for @a11yTimer.
  ///
  /// In en, this message translates to:
  /// **'{s} seconds left'**
  String a11yTimer(int s);

  /// No description provided for @a11yPlaying.
  ///
  /// In en, this message translates to:
  /// **'Clip playing'**
  String get a11yPlaying;

  /// No description provided for @feedbackCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get feedbackCorrect;

  /// No description provided for @feedbackPoints.
  ///
  /// In en, this message translates to:
  /// **'+{points}'**
  String feedbackPoints(int points);

  /// No description provided for @feedbackSpeedBonus.
  ///
  /// In en, this message translates to:
  /// **'Speed bonus +{bonus}'**
  String feedbackSpeedBonus(int bonus);

  /// No description provided for @feedbackWrong.
  ///
  /// In en, this message translates to:
  /// **'Not this one'**
  String get feedbackWrong;

  /// No description provided for @feedbackReveal.
  ///
  /// In en, this message translates to:
  /// **'It was {song} · {artist}'**
  String feedbackReveal(String song, String artist);

  /// No description provided for @feedbackTapToContinue.
  ///
  /// In en, this message translates to:
  /// **'Tap to continue · {s} s'**
  String feedbackTapToContinue(int s);

  /// No description provided for @feedbackYourPick.
  ///
  /// In en, this message translates to:
  /// **'Your pick'**
  String get feedbackYourPick;

  /// No description provided for @feedbackRevealEra.
  ///
  /// In en, this message translates to:
  /// **'It\'s from {era}'**
  String feedbackRevealEra(String era);

  /// No description provided for @feedbackTimeout.
  ///
  /// In en, this message translates to:
  /// **'Time\'s up'**
  String get feedbackTimeout;

  /// No description provided for @feedbackHintUsed.
  ///
  /// In en, this message translates to:
  /// **'Hint used · half points'**
  String get feedbackHintUsed;

  /// No description provided for @feedbackSkipped.
  ///
  /// In en, this message translates to:
  /// **'We skipped a song that wouldn\'t load or play. No points lost.'**
  String get feedbackSkipped;

  /// No description provided for @resultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Game complete'**
  String get resultsTitle;

  /// No description provided for @resultsScore.
  ///
  /// In en, this message translates to:
  /// **'{score} points'**
  String resultsScore(int score);

  /// No description provided for @resultsCorrectCount.
  ///
  /// In en, this message translates to:
  /// **'{correct} of {total} right'**
  String resultsCorrectCount(int correct, int total);

  /// No description provided for @resultsNewBest.
  ///
  /// In en, this message translates to:
  /// **'New personal best'**
  String get resultsNewBest;

  /// No description provided for @resultsRounds.
  ///
  /// In en, this message translates to:
  /// **'Your rounds'**
  String get resultsRounds;

  /// No description provided for @resultsPlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get resultsPlayAgain;

  /// No description provided for @resultsChange.
  ///
  /// In en, this message translates to:
  /// **'Change era or mode'**
  String get resultsChange;

  /// No description provided for @resultsHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get resultsHome;

  /// No description provided for @resultsGuestRank.
  ///
  /// In en, this message translates to:
  /// **'Sign in to put this score on the leaderboard'**
  String get resultsGuestRank;

  /// No description provided for @resultsWeeklyRank.
  ///
  /// In en, this message translates to:
  /// **'You\'re #{rank} this week'**
  String resultsWeeklyRank(int rank);

  /// No description provided for @resultsSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'Score saved. It will be sent when you\'re back online.'**
  String get resultsSavedOffline;

  /// No description provided for @resultsNotRanked.
  ///
  /// In en, this message translates to:
  /// **'This game couldn\'t be checked, so it won\'t count toward rankings.'**
  String get resultsNotRanked;

  /// No description provided for @lbTitle.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get lbTitle;

  /// No description provided for @lbWeekly.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get lbWeekly;

  /// No description provided for @lbAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get lbAllTime;

  /// No description provided for @lbEra.
  ///
  /// In en, this message translates to:
  /// **'Era: {era}'**
  String lbEra(String era);

  /// No description provided for @lbYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get lbYou;

  /// No description provided for @lbYourRank.
  ///
  /// In en, this message translates to:
  /// **'Your rank: #{rank}'**
  String lbYourRank(int rank);

  /// No description provided for @lbPoints.
  ///
  /// In en, this message translates to:
  /// **'{points} pts'**
  String lbPoints(int points);

  /// No description provided for @lbNotRanked.
  ///
  /// In en, this message translates to:
  /// **'Finish a game this week to get a rank.'**
  String get lbNotRanked;

  /// No description provided for @lbGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Want your name up here?'**
  String get lbGuestTitle;

  /// No description provided for @lbGuestBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to rank. Your scores come with you.'**
  String get lbGuestBody;

  /// No description provided for @lbGuestCta.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get lbGuestCta;

  /// No description provided for @lbEmpty.
  ///
  /// In en, this message translates to:
  /// **'No scores yet this week. Be the first.'**
  String get lbEmpty;

  /// No description provided for @lbOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Showing the board from {time}.'**
  String lbOffline(String time);

  /// No description provided for @lbOfflineNone.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to see the leaderboard.'**
  String get lbOfflineNone;

  /// No description provided for @lbLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the leaderboard…'**
  String get lbLoading;

  /// No description provided for @packsTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline play'**
  String get packsTitle;

  /// No description provided for @packsIntro.
  ///
  /// In en, this message translates to:
  /// **'Online, songs load as you play. Download packs to play without internet.'**
  String get packsIntro;

  /// No description provided for @packsWifiOnly.
  ///
  /// In en, this message translates to:
  /// **'Download packs on Wi-Fi only'**
  String get packsWifiOnly;

  /// No description provided for @packsMobilePrefetch.
  ///
  /// In en, this message translates to:
  /// **'Download upcoming songs on mobile data'**
  String get packsMobilePrefetch;

  /// No description provided for @packsMobilePrefetchHelp.
  ///
  /// In en, this message translates to:
  /// **'Off saves data: only songs already on your phone play.'**
  String get packsMobilePrefetchHelp;

  /// Offline play: how much the clip cache holds, and its cap
  ///
  /// In en, this message translates to:
  /// **'Cache {size} of {cap} MB'**
  String packsCacheOfCap(int size, int cap);

  /// Offline play: storage the songs take on the phone, by where they came from
  ///
  /// In en, this message translates to:
  /// **'Songs use {total} MB here: built-in {builtIn} MB, packs {packs} MB, cache {cache} MB.'**
  String packsStorageUsed(int total, int builtIn, int packs, int cache);

  /// No description provided for @packsClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get packsClearCache;

  /// No description provided for @packsBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in songs'**
  String get packsBuiltIn;

  /// No description provided for @packsBuiltInMeta.
  ///
  /// In en, this message translates to:
  /// **'{count} songs · comes with the app'**
  String packsBuiltInMeta(int count);

  /// No description provided for @packsAlways.
  ///
  /// In en, this message translates to:
  /// **'Always there'**
  String get packsAlways;

  /// No description provided for @packsOnPhone.
  ///
  /// In en, this message translates to:
  /// **'On this phone'**
  String get packsOnPhone;

  /// No description provided for @packsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available to download'**
  String get packsAvailable;

  /// No description provided for @packsSongs.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String packsSongs(int count);

  /// No description provided for @packsSize.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String packsSize(int size);

  /// No description provided for @packsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get packsDownload;

  /// No description provided for @packsProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String packsProgress(int percent);

  /// No description provided for @packsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get packsCancel;

  /// No description provided for @packsVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking files…'**
  String get packsVerifying;

  /// No description provided for @packsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get packsDownloaded;

  /// No description provided for @packsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get packsUpdateAvailable;

  /// No description provided for @packsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update · {size} MB'**
  String packsUpdate(int size);

  /// No description provided for @packsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get packsRemove;

  /// No description provided for @packsRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}? You can download it again later.'**
  String packsRemoveConfirm(String name);

  /// No description provided for @packsMobileDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Download on mobile data?'**
  String get packsMobileDataTitle;

  /// No description provided for @packsMobileDataBody.
  ///
  /// In en, this message translates to:
  /// **'This pack is {size} MB.'**
  String packsMobileDataBody(int size);

  /// No description provided for @packsMobileDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'Download now'**
  String get packsMobileDataConfirm;

  /// No description provided for @packsMobileDataWait.
  ///
  /// In en, this message translates to:
  /// **'Wait for Wi-Fi'**
  String get packsMobileDataWait;

  /// No description provided for @packsStorageFull.
  ///
  /// In en, this message translates to:
  /// **'Not enough space. Free up {size} MB and try again.'**
  String packsStorageFull(int size);

  /// No description provided for @packsOffline.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to download packs.'**
  String get packsOffline;

  /// No description provided for @authPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep your scores'**
  String get authPromptTitle;

  /// No description provided for @authPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to keep your progress on any phone and join the global leaderboard.'**
  String get authPromptBody;

  /// No description provided for @authPromptCarryOver.
  ///
  /// In en, this message translates to:
  /// **'Your scores so far come with you.'**
  String get authPromptCarryOver;

  /// No description provided for @authGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authGoogle;

  /// No description provided for @authApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get authApple;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Continue with email'**
  String get authEmail;

  /// No description provided for @authNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get authNotNow;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authEmailSubmit.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authEmailSubmit;

  /// No description provided for @authEmailCreate.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get authEmailCreate;

  /// No description provided for @authEmailForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authEmailForgot;

  /// No description provided for @authSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get authSigningIn;

  /// No description provided for @authSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String authSignedIn(String name);

  /// No description provided for @authLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t link your account. Your scores are safe on this phone, and we\'ll try again.'**
  String get authLinkFailed;

  /// No description provided for @authErrorEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email address.'**
  String get authErrorEmail;

  /// No description provided for @authErrorPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password.'**
  String get authErrorPassword;

  /// No description provided for @authNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a display name'**
  String get authNameTitle;

  /// No description provided for @authNameBody.
  ///
  /// In en, this message translates to:
  /// **'This is the name other players see on the leaderboard.'**
  String get authNameBody;

  /// No description provided for @authNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get authNameLabel;

  /// No description provided for @authNameSave.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get authNameSave;

  /// No description provided for @authNameErrorShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 2 characters.'**
  String get authNameErrorShort;

  /// No description provided for @authNameErrorTaken.
  ///
  /// In en, this message translates to:
  /// **'That name is taken. Try another.'**
  String get authNameErrorTaken;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound effects'**
  String get settingsSound;

  /// No description provided for @settingsHaptics.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get settingsHaptics;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsGuest.
  ///
  /// In en, this message translates to:
  /// **'Playing as a guest'**
  String get settingsGuest;

  /// No description provided for @settingsSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get settingsSignIn;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsSignOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out? Your scores stay saved to your account.'**
  String get settingsSignOutConfirm;

  /// No description provided for @settingsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDelete;

  /// No description provided for @settingsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and your leaderboard scores. It can\'t be undone.'**
  String get settingsDeleteBody;

  /// No description provided for @settingsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get settingsDeleteConfirm;

  /// No description provided for @settingsAdPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Ad privacy choices'**
  String get settingsAdPrivacy;

  /// No description provided for @settingsOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline play · {count, plural, =1{1 pack} other{{count} packs}} · {size} MB'**
  String settingsOffline(int count, int size);

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacy;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About and licenses'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// No description provided for @settingsMusicCredit.
  ///
  /// In en, this message translates to:
  /// **'Music used under license from [ASSOCIATION NAME].'**
  String get settingsMusicCredit;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Ads keep this game free'**
  String get consentTitle;

  /// No description provided for @consentBody.
  ///
  /// In en, this message translates to:
  /// **'Next, you\'ll choose how ads may use your data. You can change this anytime in Settings.'**
  String get consentBody;

  /// No description provided for @consentContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get consentContinue;

  /// No description provided for @adLabel.
  ///
  /// In en, this message translates to:
  /// **'Ad'**
  String get adLabel;

  /// No description provided for @adLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading ad…'**
  String get adLoading;

  /// No description provided for @adUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No ad is available right now. Try again later.'**
  String get adUnavailable;

  /// No description provided for @adNotFinished.
  ///
  /// In en, this message translates to:
  /// **'Watch the whole ad to get the hint.'**
  String get adNotFinished;

  /// No description provided for @adRewardCaption.
  ///
  /// In en, this message translates to:
  /// **'Your hint is on its way…'**
  String get adRewardCaption;

  /// No description provided for @adInterstitialCaption.
  ///
  /// In en, this message translates to:
  /// **'Ads keep this game free'**
  String get adInterstitialCaption;

  /// No description provided for @updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Time to update'**
  String get updateTitle;

  /// No description provided for @updateBody.
  ///
  /// In en, this message translates to:
  /// **'This version can\'t connect to the game server anymore. Update to use the leaderboard and get new songs.'**
  String get updateBody;

  /// No description provided for @updateCtaAndroid.
  ///
  /// In en, this message translates to:
  /// **'Update on Google Play'**
  String get updateCtaAndroid;

  /// No description provided for @updateCtaIos.
  ///
  /// In en, this message translates to:
  /// **'Update on the App Store'**
  String get updateCtaIos;

  /// No description provided for @updatePlayOffline.
  ///
  /// In en, this message translates to:
  /// **'Play offline songs'**
  String get updatePlayOffline;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. You can still play built-in and downloaded songs.'**
  String get offlineBanner;

  /// No description provided for @offlineBannerBuiltInOnly.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. You can still play the {count} built-in songs.'**
  String offlineBannerBuiltInOnly(int count);

  /// No description provided for @offlineBannerShort.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline.'**
  String get offlineBannerShort;

  /// No description provided for @offlinePending.
  ///
  /// In en, this message translates to:
  /// **'{count} games waiting to be sent'**
  String offlinePending(int count);

  /// No description provided for @offlineSynced.
  ///
  /// In en, this message translates to:
  /// **'Back online. Your scores have been sent.'**
  String get offlineSynced;

  /// No description provided for @emptyOutOfSongsTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve played every song here'**
  String get emptyOutOfSongsTitle;

  /// No description provided for @emptyOutOfSongsBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline, and you\'ve heard all the songs on this phone recently. Download a pack in Settings › Offline play for more.'**
  String get emptyOutOfSongsBody;

  /// No description provided for @emptyOutOfSongsPacks.
  ///
  /// In en, this message translates to:
  /// **'Browse packs'**
  String get emptyOutOfSongsPacks;

  /// No description provided for @emptyOutOfSongsReplay.
  ///
  /// In en, this message translates to:
  /// **'Play them again'**
  String get emptyOutOfSongsReplay;

  /// No description provided for @errorGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGenericTitle;

  /// No description provided for @errorGenericBody.
  ///
  /// In en, this message translates to:
  /// **'Please try again. If it keeps happening, restart the app.'**
  String get errorGenericBody;

  /// No description provided for @errorRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get errorRetry;

  /// No description provided for @errorDownload.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Check your connection and try again.'**
  String get errorDownload;

  /// No description provided for @errorPackCorrupt.
  ///
  /// In en, this message translates to:
  /// **'Part of this pack didn\'t download correctly. Downloading it again…'**
  String get errorPackCorrupt;

  /// No description provided for @errorSync.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send your scores. We\'ll try again automatically.'**
  String get errorSync;

  /// No description provided for @loadingApp.
  ///
  /// In en, this message translates to:
  /// **'Tuning up…'**
  String get loadingApp;

  /// No description provided for @loadingGeneric.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loadingGeneric;

  /// Title of the screen shown when this app version is too old to play
  ///
  /// In en, this message translates to:
  /// **'Update needed'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'This version of the app is out of date. Please update to keep playing.'**
  String get updateRequiredBody;

  /// Button that opens the app store listing
  ///
  /// In en, this message translates to:
  /// **'Update app'**
  String get updateRequiredButton;

  /// Shown when the catalog has no title or artist name in either script
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get nameUnknown;

  /// Title of the screen where a game is set up
  ///
  /// In en, this message translates to:
  /// **'New game'**
  String get startTitle;

  /// Heading above the Intro / Middle choice
  ///
  /// In en, this message translates to:
  /// **'What plays'**
  String get startWhatPlays;

  /// Heading above the Song / Artist / Mixed choice
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get startQuestions;

  /// Question choice: song and artist questions mixed
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get startQuestionsMixed;

  /// The player's best score so far
  ///
  /// In en, this message translates to:
  /// **'Best score: {score}'**
  String bestScore(int score);

  /// Shown when there is no best score for the chosen mode and era
  ///
  /// In en, this message translates to:
  /// **'No best score yet for this mode and era.'**
  String get startBestNone;

  /// Round screen title before the first round starts
  ///
  /// In en, this message translates to:
  /// **'Get ready'**
  String get roundGetReady;

  /// Round screen when opened with no game
  ///
  /// In en, this message translates to:
  /// **'No game is running.'**
  String get roundNoGame;

  /// Button on the no-game message
  ///
  /// In en, this message translates to:
  /// **'Start a game'**
  String get roundStartGame;

  /// Shown when a call or another app interrupted the round
  ///
  /// In en, this message translates to:
  /// **'Paused. The clip plays again when you resume. The time you already used still counts.'**
  String get roundPausedBody;

  /// Button that resumes an interrupted round
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get roundResume;

  /// Fallback message when a game fails to start
  ///
  /// In en, this message translates to:
  /// **'The game could not start.'**
  String get roundCouldNotStart;

  /// Feedback when an answer came too fast to be a person
  ///
  /// In en, this message translates to:
  /// **'Too fast to count. 0 points'**
  String get feedbackTooFast;

  /// Feedback heading for a right answer, with the points earned
  ///
  /// In en, this message translates to:
  /// **'Correct! +{points}'**
  String feedbackCorrectPoints(int points);

  /// Results screen opened with no finished game
  ///
  /// In en, this message translates to:
  /// **'No finished game to show.'**
  String get resultsNone;

  /// Results note: rounds left out because their clip was missing or would not play
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 round was skipped because a clip could not be played.} other{{count} rounds were skipped because a clip could not be played.}}'**
  String resultsSkipped(int count);

  /// Results note when a response was too fast to be a person
  ///
  /// In en, this message translates to:
  /// **'Some answers were too fast to count.'**
  String get resultsFlagged;

  /// Results note when saving the game on the device failed; detail is the technical reason
  ///
  /// In en, this message translates to:
  /// **'This game could not be saved on the phone: {detail}'**
  String resultsSaveError(String detail);

  /// Results row for a wrong answer; name is the song or singer picked
  ///
  /// In en, this message translates to:
  /// **'You chose {name}'**
  String resultsYouChose(String name);

  /// A game cannot start because no songs are on the phone and none can be fetched
  ///
  /// In en, this message translates to:
  /// **'There are no songs to play yet. Connect to the internet and try again.'**
  String get sessionErrorNoSongs;

  /// A game cannot start: too few songs
  ///
  /// In en, this message translates to:
  /// **'There aren\'t enough songs to make a round. Connect to the internet and try again.'**
  String get sessionErrorTooFewSongs;

  /// A game cannot start: too few different artists for artist questions
  ///
  /// In en, this message translates to:
  /// **'There aren\'t enough different artists for artist questions. Choose Song questions or connect to the internet.'**
  String get sessionErrorTooFewArtists;

  /// A game cannot start: the chosen era has no songs; era is the era's name
  ///
  /// In en, this message translates to:
  /// **'There are no songs for {era}. Choose another era.'**
  String sessionErrorNoSongsInEra(String era);

  /// A game ended because no clip would play
  ///
  /// In en, this message translates to:
  /// **'None of the {count} clips could be played. Check your connection and try once more.'**
  String sessionErrorClipsFailed(int count);

  /// A game failed for an unexpected reason; detail is the technical message
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {detail}'**
  String sessionErrorUnexpected(String detail);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['am', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'am':
      return AppLocalizationsAm();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
