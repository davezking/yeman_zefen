// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Amharic (`am`).
class AppLocalizationsAm extends AppLocalizations {
  AppLocalizationsAm([String locale = 'am']) : super(locale);

  @override
  String get appTitle => 'የማን ዘፈን';

  @override
  String get homeTagline => 'ቅንጭቡን ያዳምጡ እና ዘፈኑን ይምረጡ።';

  @override
  String get playButton => 'ጀምር';

  @override
  String get appName => 'የማን ዘፈን';

  @override
  String get appTagline => 'የማን ዘፈን ነው?';

  @override
  String get onboardLangTitle => 'ቋንቋ ይምረጡ';

  @override
  String get onboardLangAmharic => 'አማርኛ';

  @override
  String get onboardLangEnglish => 'English';

  @override
  String get onboardLangLater => 'ይህን በማንኛውም ጊዜ በቅንብሮች ውስጥ መቀየር ይችላሉ።';

  @override
  String get onboardWelcomeTitle => 'ዘፈኑን ከመጀመሪያዎቹ ድምፆች ይለዩ።';

  @override
  String get onboardWelcomeBody =>
      'አጭር ቅንጭብ ያዳምጡ፣ ከዚያ ዘፈኑን ወይም ዘፋኙን ይምረጡ። መመዝገብ አያስፈልግም።';

  @override
  String get onboardWelcomeStart => 'መጫወት ይጀምሩ';

  @override
  String get commonNext => 'ቀጣይ';

  @override
  String get homeHello => 'ለዘፈን ዝግጁ ነዎት?';

  @override
  String get homeQuickPlay => 'ይጫወቱ';

  @override
  String get homeQuickPlayLabel => 'ይጫወቱ የሚጀምረው';

  @override
  String homeQuickPlaySettings(String era, String mode, String difficulty) {
    return '$era · $mode · $difficulty';
  }

  @override
  String get homeChooseMode => 'ሌሎች የአጨዋወት መንገዶች';

  @override
  String get homeModeIntroShort => 'የዘፈኑ መጀመሪያ';

  @override
  String get homeModeMiddleShort => 'ይከብዳል · +25% ነጥብ';

  @override
  String get homeModeEraShort => 'ዘመኑን ይለዩ';

  @override
  String get homeLeaderboard => 'የደረጃ ሰንጠረዥ';

  @override
  String get homeLeaderboardGuest => 'ደረጃ ለማግኘት ይግቡ';

  @override
  String get homeLeaderboardOffline => 'ኢንተርኔት ያስፈልጋል';

  @override
  String get homeBestLabel => 'ምርጥ ውጤትዎ';

  @override
  String get homeBestNone => 'የመጀመሪያ ምርጥ ውጤትዎን ለማስመዝገብ አንድ ጨዋታ ይጫወቱ።';

  @override
  String get homeBuiltIn => 'አብረው የመጡ ዘፈኖች';

  @override
  String get homeQuickPlayModeIntro => 'መግቢያ';

  @override
  String get homeQuickPlayModeMiddle => 'ከመሀል';

  @override
  String get homeQuickPlayModeEra => 'የየትኛው ዘመን?';

  @override
  String get difficultyEasyShort => 'ቀላል';

  @override
  String get difficultyMediumShort => 'መካከለኛ';

  @override
  String get difficultyHardShort => 'ከባድ';

  @override
  String get navHome => 'መነሻ';

  @override
  String get navPlay => 'ይጫወቱ';

  @override
  String get navSettings => 'ቅንብሮች';

  @override
  String get navBack => 'ይመለሱ';

  @override
  String get modeTitle => 'እንዴት መጫወት ይፈልጋሉ?';

  @override
  String get modeIntroName => 'መግቢያውን ይገምቱ';

  @override
  String get modeIntroDesc => 'የዘፈኑ መጀመሪያ። የተለመደው ጨዋታ።';

  @override
  String get modeMiddleName => 'ከመሀል ይገምቱ';

  @override
  String get modeMiddleDesc => 'ከዘፈኑ መሀል የተወሰደ ቅንጭብ። ስለሚከብድ ተጨማሪ ነጥብ ያስገኛል።';

  @override
  String get modeMiddleTag => '+25%';

  @override
  String get modeEraName => 'የየትኛው ዘመን?';

  @override
  String get modeEraDesc => 'ዘፈኑን ሰምተው ዘመኑን ይለዩ።';

  @override
  String get modeBonus => 'ተጨማሪ';

  @override
  String get modeGuessLabel => 'የሚገምቱት';

  @override
  String get modeGuessSong => 'ዘፈኑን';

  @override
  String get modeGuessArtist => 'ዘፋኙን';

  @override
  String get eraTitle => 'ዘመን ይምረጡ';

  @override
  String get eraAll => 'ሁሉም ዘመኖች';

  @override
  String get eraGolden => 'ወርቃማው ዘመን';

  @override
  String get eraGoldenRange => 'ከ1980 በፊት';

  @override
  String get era80s => 'የ80ዎቹ';

  @override
  String get era90s => 'የ90ዎቹ';

  @override
  String get era2000s => 'የ2000ዎቹ';

  @override
  String get eraModern => 'ዘመናዊ';

  @override
  String get eraModernRange => 'ከ2010 ወዲህ';

  @override
  String get eraOfflineUnavailable => 'ኢንተርኔት ወይም የወረደ ጥቅል ያስፈልጋል';

  @override
  String get genreTitle => 'ዘውግ (አማራጭ)';

  @override
  String get genreAny => 'ማንኛውም ዘውግ';

  @override
  String get genreTizita => 'ትዝታ';

  @override
  String get genreEthiojazz => 'ኢትዮ ጃዝ';

  @override
  String get genreTraditional => 'ባሕላዊ';

  @override
  String get genrePop => 'ፖፕ';

  @override
  String get genreHiphop => 'ሂፕ ሆፕ';

  @override
  String get difficultyTitle => 'የቅንጭቡ ርዝመት';

  @override
  String get difficultyEasy => 'ቀላል · 10 ሰከንድ';

  @override
  String get difficultyMedium => 'መካከለኛ · 5 ሰከንድ';

  @override
  String get difficultyHard => 'ከባድ · 3 ሰከንድ';

  @override
  String setupStart(int total) {
    return 'ይጀምሩ · $total ዙሮች';
  }

  @override
  String get setupTooFewSongs =>
      'ለዚህ ምርጫ ገና በቂ ዘፈኖች የሉም። \"ሁሉም ዘመኖች\"ን ወይም ሌላ ዘውግ ይሞክሩ።';

  @override
  String roundCounter(int n, int total) {
    return '$n / $total';
  }

  @override
  String roundScore(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '$pointsString ነጥብ';
  }

  @override
  String get roundLoading => 'ቀጣዩን ዘፈን በማዘጋጀት ላይ…';

  @override
  String get roundLoadingNote =>
      'በ10 ሰከንድ ውስጥ ካልተጫነ ይህን ዙር እንዘልለዋለን። ነጥብ አይቀነስብዎትም።';

  @override
  String get roundListen => 'ያዳምጡ…';

  @override
  String get roundQuestionSong => 'ይህ የትኛው ዘፈን ነው?';

  @override
  String get roundQuestionArtist => 'ይህን ዘፈን የዘፈነው ማን ነው?';

  @override
  String get roundQuestionEra => 'ይህ ዘፈን የየትኛው ዘመን ነው?';

  @override
  String roundSecondsLeft(int s) {
    return '$s ሰከንድ';
  }

  @override
  String get roundHint => 'ፍንጭ፦ 2 መልሶችን ያስወግዱ';

  @override
  String get roundHintTerms => 'አጭር ማስታወቂያ ይመልከቱ። የዚህ ዙር ነጥብ በግማሽ ይቀንሳል።';

  @override
  String get roundHintPaused =>
      'ለመወሰን እስከ 8 ሰከንድ፣ እንዲሁም ማስታወቂያው እስኪያልቅ ድረስ ሰዓቱ ይቆማል።';

  @override
  String roundHintClosesIn(int s) {
    return '$s ሰከንድ';
  }

  @override
  String get roundTimerPaused => 'ቆሟል';

  @override
  String get roundHintWatch => 'ማስታወቂያ ይመልከቱ';

  @override
  String get roundHintCancel => 'አይ፣ ይቅር';

  @override
  String get roundHintButton => 'ፍንጭ';

  @override
  String get roundLeave => 'ከጨዋታው ይውጡ';

  @override
  String get roundLeaveTitle => 'ጨዋታውን ያቋርጣሉ?';

  @override
  String get roundLeaveBody => 'የዚህ ጨዋታ ውጤት አይቀመጥም።';

  @override
  String get roundLeaveConfirm => 'ይውጡ';

  @override
  String get roundLeaveCancel => 'መጫወት ይቀጥሉ';

  @override
  String a11yAnswer(int n, String text) {
    return 'መልስ $n፦ $text';
  }

  @override
  String a11yTimer(int s) {
    return '$s ሰከንድ ቀርቷል';
  }

  @override
  String get a11yPlaying => 'ቅንጭቡ እየተጫወተ ነው';

  @override
  String get feedbackCorrect => 'ትክክል';

  @override
  String feedbackPoints(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '+$pointsString';
  }

  @override
  String feedbackSpeedBonus(int bonus) {
    return 'የፍጥነት ጉርሻ +$bonus';
  }

  @override
  String get feedbackWrong => 'ይህ አይደለም';

  @override
  String feedbackReveal(String song, String artist) {
    return 'መልሱ፦ $song · $artist';
  }

  @override
  String feedbackTapToContinue(int s) {
    return 'ለመቀጠል ይንኩ · $s ሰከንድ';
  }

  @override
  String get feedbackYourPick => 'የእርስዎ ምርጫ';

  @override
  String feedbackRevealEra(String era) {
    return '$era ዘፈን ነው';
  }

  @override
  String get feedbackTimeout => 'ጊዜው አልቋል';

  @override
  String get feedbackHintUsed => 'ፍንጭ ተጠቅመዋል · ግማሽ ነጥብ';

  @override
  String get feedbackSkipped => 'ሊጫን ወይም ሊጫወት ያልቻለ ዘፈን ዘለልን። ነጥብ አልተቀነሰም።';

  @override
  String get resultsTitle => 'ጨዋታው ተጠናቋል';

  @override
  String resultsScore(int score) {
    final intl.NumberFormat scoreNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String scoreString = scoreNumberFormat.format(score);

    return '$scoreString ነጥብ';
  }

  @override
  String resultsCorrectCount(int correct, int total) {
    return 'ከ$total $correct ትክክል';
  }

  @override
  String get resultsNewBest => 'አዲስ የግል ምርጥ ውጤት';

  @override
  String get resultsRounds => 'የእርስዎ ዙሮች';

  @override
  String get resultsPlayAgain => 'እንደገና ይጫወቱ';

  @override
  String get resultsChange => 'ዘመን ወይም ጨዋታ ይቀይሩ';

  @override
  String get resultsHome => 'መነሻ';

  @override
  String get resultsGuestRank => 'ይህ ውጤት በደረጃ ሰንጠረዡ ላይ እንዲሰፍር ይግቡ';

  @override
  String resultsWeeklyRank(int rank) {
    return 'በዚህ ሳምንት $rankኛ ነዎት';
  }

  @override
  String get resultsSavedOffline => 'ውጤቱ ተቀምጧል። ኢንተርኔት ሲገኝ ይላካል።';

  @override
  String get resultsNotRanked => 'ይህ ጨዋታ ሊረጋገጥ ስላልቻለ ለደረጃ አይቆጠርም።';

  @override
  String get lbTitle => 'የደረጃ ሰንጠረዥ';

  @override
  String get lbWeekly => 'የዚህ ሳምንት';

  @override
  String get lbAllTime => 'የምንጊዜም';

  @override
  String lbEra(String era) {
    return 'ዘመን፦ $era';
  }

  @override
  String get lbYou => 'እርስዎ';

  @override
  String lbYourRank(int rank) {
    return 'ደረጃዎ፦ $rankኛ';
  }

  @override
  String lbPoints(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '$pointsString ነጥብ';
  }

  @override
  String get lbNotRanked => 'ደረጃ ለማግኘት በዚህ ሳምንት አንድ ጨዋታ ያጠናቁ።';

  @override
  String get lbGuestTitle => 'ስምዎ እዚህ እንዲሰፍር ይፈልጋሉ?';

  @override
  String get lbGuestBody => 'ደረጃ ለማግኘት ይግቡ። ውጤትዎ አይጠፋም።';

  @override
  String get lbGuestCta => 'ይግቡ';

  @override
  String get lbEmpty => 'በዚህ ሳምንት እስካሁን ውጤት የለም። የመጀመሪያው ይሁኑ።';

  @override
  String lbOffline(String time) {
    return 'ከኢንተርኔት ውጭ ነዎት። የ$time ሰንጠረዥ እየታየ ነው።';
  }

  @override
  String get lbOfflineNone => 'የደረጃ ሰንጠረዡን ለማየት ከኢንተርኔት ጋር ይገናኙ።';

  @override
  String get lbLoading => 'የደረጃ ሰንጠረዡን በመጫን ላይ…';

  @override
  String get packsTitle => 'ያለ ኢንተርኔት መጫወት';

  @override
  String get packsIntro =>
      'ኢንተርኔት ሲኖር ዘፈኖች በሚጫወቱበት ጊዜ ይጫናሉ። ያለ ኢንተርኔት ለመጫወት ጥቅሎችን ያውርዱ።';

  @override
  String get packsWifiOnly => 'ጥቅሎችን በዋይፋይ ብቻ ያውርዱ';

  @override
  String get packsMobilePrefetch => 'ቀጣይ ዘፈኖችን በሞባይል ዳታ ያውርዱ';

  @override
  String get packsMobilePrefetchHelp =>
      'ሲጠፋ ዳታ ይቆጥባል፤ በስልክዎ ላይ ያሉ ዘፈኖች ብቻ ይጫወታሉ።';

  @override
  String packsCache(int size) {
    return 'ማቆያ $size ሜባ';
  }

  @override
  String get packsClearCache => 'ማቆያውን ያጽዱ';

  @override
  String get packsBuiltIn => 'አብረው የመጡ ዘፈኖች';

  @override
  String packsBuiltInMeta(int count) {
    return '$count ዘፈኖች · ከመተግበሪያው ጋር';
  }

  @override
  String get packsAlways => 'ሁልጊዜ አለ';

  @override
  String get packsOnPhone => 'በዚህ ስልክ ላይ';

  @override
  String get packsAvailable => 'ለማውረድ የሚገኙ';

  @override
  String packsSongs(int count) {
    return '$count ዘፈኖች';
  }

  @override
  String packsSize(int size) {
    return '$size ሜባ';
  }

  @override
  String get packsDownload => 'ያውርዱ';

  @override
  String packsProgress(int percent) {
    return '$percent%';
  }

  @override
  String get packsCancel => 'ይሰርዙ';

  @override
  String get packsVerifying => 'ፋይሎችን በማረጋገጥ ላይ…';

  @override
  String get packsDownloaded => 'ወርዷል';

  @override
  String get packsUpdateAvailable => 'ማሻሻያ አለ';

  @override
  String packsUpdate(int size) {
    return 'ያዘምኑ · $size ሜባ';
  }

  @override
  String get packsRemove => 'ያስወግዱ';

  @override
  String packsRemoveConfirm(String name) {
    return '$name ይወገድ? በኋላ እንደገና ማውረድ ይችላሉ።';
  }

  @override
  String get packsMobileDataTitle => 'በሞባይል ዳታ ይውረድ?';

  @override
  String packsMobileDataBody(int size) {
    return 'ይህ ጥቅል $size ሜባ ነው።';
  }

  @override
  String get packsMobileDataConfirm => 'አሁን ያውርዱ';

  @override
  String get packsMobileDataWait => 'ዋይፋይ ይጠብቁ';

  @override
  String packsStorageFull(int size) {
    return 'በቂ ቦታ የለም። $size ሜባ ነፃ አድርገው እንደገና ይሞክሩ።';
  }

  @override
  String get packsOffline => 'ጥቅሎችን ለማውረድ ከኢንተርኔት ጋር ይገናኙ።';

  @override
  String get authPromptTitle => 'ውጤቶችዎን ያስቀምጡ';

  @override
  String get authPromptBody =>
      'እድገትዎን በማንኛውም ስልክ ለማቆየትና በዓለም አቀፉ የደረጃ ሰንጠረዥ ለመሳተፍ ይግቡ።';

  @override
  String get authPromptCarryOver => 'እስካሁን ያገኙት ውጤት አይጠፋም።';

  @override
  String get authGoogle => 'በGoogle ይቀጥሉ';

  @override
  String get authApple => 'በApple ይቀጥሉ';

  @override
  String get authEmail => 'በኢሜይል ይቀጥሉ';

  @override
  String get authNotNow => 'አሁን አይደለም';

  @override
  String get authEmailLabel => 'ኢሜይል';

  @override
  String get authPasswordLabel => 'የይለፍ ቃል';

  @override
  String get authEmailSubmit => 'ይግቡ';

  @override
  String get authEmailCreate => 'አዲስ ነዎት? መለያ ይፍጠሩ';

  @override
  String get authEmailForgot => 'የይለፍ ቃልዎን ረስተዋል?';

  @override
  String get authSigningIn => 'በመግባት ላይ…';

  @override
  String authSignedIn(String name) {
    return 'እንደ $name ገብተዋል';
  }

  @override
  String get authLinkFailed =>
      'መለያዎን ማገናኘት አልተቻለም። ውጤቶችዎ በዚህ ስልክ ላይ ደህና ናቸው፤ እንደገና እንሞክራለን።';

  @override
  String get authErrorEmail => 'የኢሜይል አድራሻዎን ያረጋግጡ።';

  @override
  String get authErrorPassword => 'ኢሜይሉ ወይም የይለፍ ቃሉ ትክክል አይደለም።';

  @override
  String get authNameTitle => 'የሚታይ ስም ይምረጡ';

  @override
  String get authNameBody => 'ይህ በደረጃ ሰንጠረዡ ላይ ሌሎች ተጫዋቾች የሚያዩት ስም ነው።';

  @override
  String get authNameLabel => 'የሚታይ ስም';

  @override
  String get authNameSave => 'ስሙን ያስቀምጡ';

  @override
  String get authNameErrorShort => 'ቢያንስ 2 ፊደላት ይጠቀሙ።';

  @override
  String get authNameErrorTaken => 'ይህ ስም ተይዟል። ሌላ ይሞክሩ።';

  @override
  String get settingsTitle => 'ቅንብሮች';

  @override
  String get settingsLanguage => 'ቋንቋ';

  @override
  String get settingsSound => 'የድምፅ ውጤቶች';

  @override
  String get settingsHaptics => 'ንዝረት';

  @override
  String get settingsAccount => 'መለያ';

  @override
  String get settingsGuest => 'በእንግድነት እየተጫወቱ ነው';

  @override
  String get settingsSignIn => 'ይግቡ';

  @override
  String get settingsSignOut => 'ይውጡ';

  @override
  String get settingsSignOutConfirm => 'ይወጣሉ? ውጤቶችዎ በመለያዎ ላይ ተቀምጠው ይቆያሉ።';

  @override
  String get settingsDelete => 'መለያ ይሰርዙ';

  @override
  String get settingsDeleteBody =>
      'ይህ መለያዎንና የደረጃ ውጤቶችዎን እስከመጨረሻው ይሰርዛል። መመለስ አይቻልም።';

  @override
  String get settingsDeleteConfirm => 'መለያዬን ይሰርዙ';

  @override
  String get settingsAdPrivacy => 'የማስታወቂያ ግላዊነት ምርጫዎች';

  @override
  String settingsOffline(int count, int size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ጥቅሎች',
      one: '1 ጥቅል',
    );
    return 'ያለ ኢንተርኔት መጫወት · $_temp0 · $size ሜባ';
  }

  @override
  String get settingsPrivacy => 'የግላዊነት ፖሊሲ';

  @override
  String get settingsAbout => 'ስለ መተግበሪያው እና ፈቃዶች';

  @override
  String settingsVersion(String version) {
    return 'ስሪት $version';
  }

  @override
  String get settingsMusicCredit => 'ሙዚቃዎቹ ጥቅም ላይ የዋሉት በ[የማህበሩ ስም] ፈቃድ ነው።';

  @override
  String get consentTitle => 'ጨዋታው ነፃ የሆነው በማስታወቂያ ነው';

  @override
  String get consentBody =>
      'በመቀጠል ማስታወቂያዎች መረጃዎን እንዴት እንደሚጠቀሙ ይመርጣሉ። ይህን በማንኛውም ጊዜ በቅንብሮች ውስጥ መቀየር ይችላሉ።';

  @override
  String get consentContinue => 'ይቀጥሉ';

  @override
  String get adLabel => 'ማስታወቂያ';

  @override
  String get adLoading => 'ማስታወቂያ በመጫን ላይ…';

  @override
  String get adUnavailable => 'አሁን ማስታወቂያ የለም። ቆይተው እንደገና ይሞክሩ።';

  @override
  String get adNotFinished => 'ፍንጩን ለማግኘት ማስታወቂያውን እስከመጨረሻው ይመልከቱ።';

  @override
  String get adRewardCaption => 'ፍንጭዎ እየመጣ ነው…';

  @override
  String get adInterstitialCaption => 'ጨዋታው ነፃ የሆነው በማስታወቂያ ነው';

  @override
  String get updateTitle => 'ማዘመን ያስፈልጋል';

  @override
  String get updateBody =>
      'ይህ ስሪት ከጨዋታው አገልጋይ ጋር መገናኘት አይችልም። የደረጃ ሰንጠረዡን ለመጠቀምና አዲስ ዘፈኖችን ለማግኘት ያዘምኑ።';

  @override
  String get updateCtaAndroid => 'በGoogle Play ያዘምኑ';

  @override
  String get updateCtaIos => 'በApp Store ያዘምኑ';

  @override
  String get updatePlayOffline => 'ያለ ኢንተርኔት ዘፈኖች ይጫወቱ';

  @override
  String get offlineBanner =>
      'ከኢንተርኔት ውጭ ነዎት። አብረው የመጡትንና የወረዱትን ዘፈኖች መጫወት ይችላሉ።';

  @override
  String offlineBannerBuiltInOnly(int count) {
    return 'ከኢንተርኔት ውጭ ነዎት። አብረው የመጡትን $count ዘፈኖች መጫወት ይችላሉ።';
  }

  @override
  String get offlineBannerShort => 'ከኢንተርኔት ውጭ ነዎት።';

  @override
  String offlinePending(int count) {
    return '$count ጨዋታዎች ለመላክ እየጠበቁ ነው';
  }

  @override
  String get offlineSynced => 'ኢንተርኔት ተመልሷል። ውጤቶችዎ ተልከዋል።';

  @override
  String get emptyOutOfSongsTitle => 'እዚህ ያሉትን ዘፈኖች በሙሉ ተጫውተዋል';

  @override
  String get emptyOutOfSongsBody =>
      'ከኢንተርኔት ውጭ ነዎት፤ በዚህ ስልክ ላይ ያሉትን ዘፈኖች በሙሉ በቅርቡ ሰምተዋል። ለተጨማሪ ዘፈኖች በቅንብሮች › ያለ ኢንተርኔት መጫወት ውስጥ ጥቅል ያውርዱ።';

  @override
  String get emptyOutOfSongsPacks => 'ጥቅሎችን ይመልከቱ';

  @override
  String get emptyOutOfSongsReplay => 'ዘፈኖቹን እንደገና ይጫወቱ';

  @override
  String get errorGenericTitle => 'የሆነ ችግር ተፈጥሯል';

  @override
  String get errorGenericBody =>
      'እባክዎ እንደገና ይሞክሩ። ችግሩ ከቀጠለ መተግበሪያውን ዘግተው ይክፈቱ።';

  @override
  String get errorRetry => 'እንደገና ይሞክሩ';

  @override
  String get errorDownload => 'ማውረዱ አልተሳካም። ግንኙነትዎን አረጋግጠው እንደገና ይሞክሩ።';

  @override
  String get errorPackCorrupt => 'የጥቅሉ የተወሰነ ክፍል በትክክል አልወረደም። እንደገና በማውረድ ላይ…';

  @override
  String get errorSync => 'ውጤቶችዎን መላክ አልተቻለም። በራሱ እንደገና ይሞክራል።';

  @override
  String get loadingApp => 'በመዘጋጀት ላይ…';

  @override
  String get loadingGeneric => 'በመጫን ላይ…';
}
