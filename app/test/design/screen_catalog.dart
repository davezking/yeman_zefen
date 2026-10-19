import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yeman_zefen/core/theme/tokens.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/prototype/mock_data.dart';
import 'package:yeman_zefen/prototype/models.dart';
import 'package:yeman_zefen/features/game/presentation/home_screen.dart';
import 'package:yeman_zefen/features/leaderboard/ui/leaderboard_screen.dart';
import 'package:yeman_zefen/prototype/screens/message_screens.dart';
import 'package:yeman_zefen/features/game/presentation/mode_select_screen.dart';
import 'package:yeman_zefen/features/packs/presentation/offline_play_screen.dart';
import 'package:yeman_zefen/prototype/screens/onboarding_screens.dart';
import 'package:yeman_zefen/prototype/screens/results_screen.dart';
import 'package:yeman_zefen/features/game/presentation/round_screen.dart';
import 'package:yeman_zefen/features/settings/presentation/settings_screen.dart';
import 'package:yeman_zefen/features/game/presentation/setup_screen.dart';
import 'package:yeman_zefen/features/account/ui/sign_in_sheet.dart';

void _noop() {}
void _noopString(String _) {}
void _noopBool(bool _) {}

/// One screen in one state, as the design review shows it.
class DesignScreen {
  const DesignScreen(this.slug, this.title, this.board, this.build);

  /// `<screen>-<state>`, the start of the screenshot's file name.
  final String slug;
  final String title;

  /// The approved design (`docs/design/artifacts/<board>.dc.html`, picture in
  /// `docs/design/screens/<board>.webp`), or null for a state the boards do not
  /// draw (it is specified in `docs/design/screens.md`).
  final String? board;

  /// Builds a fresh widget (plain data and no-op callbacks).
  final Widget Function() build;
}

/// The phone sizes of the review: the design's 360 x 780 and a large phone.
const designSizes = <String, Size>{
  '360x780': Size(360, 780),
  '430x932': Size(430, 932),
};

/// Where the screenshots live (the golden files): `docs/design/flutter/`.
/// Tests run with `app/` as the working directory.
final Uri designScreenshotsDir = Directory.current.uri.resolve(
  '../docs/design/flutter/',
);

/// Every screen and state of the prototype, in the order of the boards.
final List<DesignScreen> designScreens = _buildDesignScreens();

List<DesignScreen> _buildDesignScreens() {
  const quickPlay = PlaySettings(
    generationId: EraId.eighties,
    mode: GameMode.intro,
  );

  Widget home({
    UserInfo user = mockGuest,
    bool offline = false,
    bool packs = false,
  }) => HomeScreen(
    user: user,
    quickPlay: quickPlay,
    offline: offline,
    hasDownloadedPacks: packs,
    builtInSongCount: mockBuiltInSongCount,
    onPlay: _noop,
    onModeSelected: (_) {},
    onLeaderboard: _noop,
    onSettings: _noop,
  );

  Widget modeSelect(GameMode mode) => ModeSelectScreen(
    mode: mode,
    guess: GuessTarget.song,
    onModeChanged: (_) {},
    onGuessChanged: (_) {},
    onBack: _noop,
    onNext: _noop,
  );

  Widget setup({Set<int> disabled = const {}, bool tooFew = false}) =>
      SetupScreen(
        mode: GameMode.intro,
        generationId: EraId.eighties,
        genre: Genre.any,
        difficulty: Difficulty.easy,
        disabledEras: disabled,
        tooFewSongs: tooFew,
        onEra: (_) {},
        onGenre: (_) {},
        onDifficulty: (_) {},
        onBack: _noop,
        onStart: _noop,
      );

  Widget settings({
    UserInfo user = mockGuest,
    bool update = false,
    String lang = 'en',
  }) => SettingsScreen(
    languageCode: lang,
    soundOn: true,
    hapticsOn: false,
    user: user,
    offlinePackCount: 2,
    offlineSizeMb: 27,
    offlineUpdateAvailable: update,
    version: mockAppVersion,
    onLanguage: _noopString,
    onSound: _noopBool,
    onHaptics: _noopBool,
    onSignIn: _noop,
    onSignOut: _noop,
    onDeleteAccount: _noop,
    onOfflinePlay: _noop,
    onAdPrivacy: _noop,
    onPrivacy: _noop,
    onAbout: _noop,
    onHome: _noop,
    onPlay: _noop,
  );

  Widget offlinePlay({
    List<PackItem> packs = mockPacks,
    Connection connection = Connection.wifi,
  }) => OfflinePlayScreen(
    wifiOnly: true,
    mobilePrefetch: true,
    cache: mockCache,
    builtInSongCount: mockBuiltInSongCount,
    packs: packs,
    connection: connection,
    onBack: _noop,
    onWifiOnly: _noopBool,
    onMobilePrefetch: _noopBool,
    onClearCache: _noop,
    onDownload: _noopString,
    onCancel: _noopString,
    onRetry: _noopString,
    onRemove: _noopString,
  );

  PackItem failed(PackProblem problem) => PackItem(
    id: 'p-90s',
    nameAm: 'የ90ዎቹ',
    nameEn: "The '90s",
    generationId: EraId.nineties,
    songCount: 45,
    sizeMb: 14,
    status: PackStatus.failed,
    problem: problem,
    shortfallMb: 8,
  );

  // ---- the round ----

  RoundView roundView({
    RoundPhase phase = RoundPhase.answering,
    int? picked,
    Set<int> removed = const {},
    bool hintUsed = false,
    bool playing = true,
    bool paused = false,
    RoundOverlay overlay = RoundOverlay.none,
    int overlaySeconds = 0,
    int points = 0,
    QuestionKind kind = QuestionKind.artist,
    int secondsLeft = 7,
    int feedbackSeconds = 0,
    int score = 420,
    // The longest names in the catalog, to push the tiles to their limit.
    List<int> trackIndexes = const [3, 0, 8, 11],
  }) => RoundView(
    roundNumber: 4,
    totalRounds: 10,
    score: score,
    eraFilterId: EraId.eighties,
    difficulty: Difficulty.easy,
    kind: kind,
    options: kind == QuestionKind.era
        ? [
            for (final i in [2, 1, 3, 5]) RoundOption.era(i),
          ]
        : [for (final i in trackIndexes) RoundOption.track(mockTracks[i])],
    correctIndex: 1,
    track: mockTracks[0],
    phase: phase,
    clipPlaying: playing,
    timeFraction: secondsLeft / 15,
    secondsLeft: secondsLeft,
    timerPaused: paused,
    pickedIndex: picked,
    removed: removed,
    hintAvailable: phase == RoundPhase.answering && !hintUsed,
    hintUsed: hintUsed,
    points: points,
    speedBonus: points > 100 ? points - 100 : 0,
    feedbackSecondsLeft: feedbackSeconds,
    overlay: overlay,
    overlaySeconds: overlaySeconds,
  );

  Widget round(RoundView v) => RoundScreen(
    view: v,
    onAnswer: (_) {},
    onHint: _noop,
    onContinue: _noop,
    onLeaveRequested: _noop,
    onLeaveConfirmed: _noop,
    onLeaveCancelled: _noop,
    onWatchHintAd: _noop,
    onDeclineHint: _noop,
  );

  // ---- results ----

  Widget results({
    UserInfo user = mockGuest,
    bool best = false,
    ScoreSync sync = ScoreSync.provisional,
    int score = 1240,
  }) => ResultsScreen(
    view: ResultsView(
      score: score,
      rounds: mockResultRounds,
      user: user,
      newBest: best,
      sync: sync,
    ),
    onPlayAgain: _noop,
    onChange: _noop,
    onHome: _noop,
    onSignIn: _noop,
    onLeaderboard: _noop,
  );

  // ---- the leaderboard ----

  Widget board({
    UserInfo user = mockGuest,
    LeaderboardState state = LeaderboardState.ready,
    LeaderboardScope scope = LeaderboardScope.weekly,
    int era = EraId.all,
    bool noRow = false,
  }) => LeaderboardScreen(
    view: LeaderboardView(
      scope: scope,
      generationId: era,
      entries:
          state == LeaderboardState.ready ||
              state == LeaderboardState.offlineCached
          ? mockLeaderboard(scope, era)
          : const [],
      user: user,
      me: user.isGuest || noRow ? null : mockMyEntry(scope, era, 7),
      state: state,
      cachedAt: '3:20 PM',
    ),
    onBack: _noop,
    onScope: (_) {},
    onEra: (_) {},
    onSignIn: _noop,
  );

  // ---- the sign-in sheets, as they sit over a screen ----

  Widget sheetOver(Widget behind, Widget content) => Stack(
    children: [
      behind,
      const Positioned.fill(
        child: ColoredBox(color: ColorTokens.backgroundScrim),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        // The Material a bottom sheet route provides, for the text fields.
        child: Material(
          type: MaterialType.transparency,
          child: AppSheet(child: content),
        ),
      ),
    ],
  );

  return [
    DesignScreen('app-start', "app start", null, () => const AppStartScreen()),
    DesignScreen(
      'language-english',
      "first launch: language, English",
      'H01-Language',
      () => LanguageScreen(
        languageCode: 'en',
        onLanguage: _noopString,
        onNext: _noop,
      ),
    ),
    DesignScreen(
      'language-amharic',
      "first launch: language, Amharic",
      'H01-Language',
      () => LanguageScreen(
        languageCode: 'am',
        onLanguage: _noopString,
        onNext: _noop,
      ),
    ),
    DesignScreen(
      'welcome',
      "first launch: welcome",
      'H02-Welcome',
      () => WelcomeScreen(
        sampleAnswers: const ['Mahmoud Ahmed', 'Aster Aweke'],
        onStart: _noop,
      ),
    ),
    DesignScreen(
      'ad-consent',
      "ad consent",
      'H15-AdConsent',
      () => ConsentScreen(onContinue: _noop),
    ),
    DesignScreen(
      'ad-consent-google-form',
      "ad consent: Google's form",
      'H15-AdConsent',
      () => sheetOver(
        ConsentScreen(onContinue: _noop),
        UmpFormPlaceholder(onDone: _noop),
      ),
    ),
    DesignScreen(
      'forced-update-android',
      "forced update, Android",
      'H16-ForcedUpdate',
      () =>
          ForcedUpdateScreen(ios: false, onUpdate: _noop, onPlayOffline: _noop),
    ),
    DesignScreen(
      'forced-update-ios',
      "forced update, iOS",
      'H16-ForcedUpdate',
      () =>
          ForcedUpdateScreen(ios: true, onUpdate: _noop, onPlayOffline: _noop),
    ),
    DesignScreen(
      'out-of-songs',
      "out of songs",
      'H21-OutOfSongs',
      () => OutOfSongsScreen(onBrowsePacks: _noop, onReplay: _noop),
    ),
    DesignScreen(
      'error-generic',
      "generic error",
      null,
      () => ErrorScreen(onRetry: _noop),
    ),
    DesignScreen(
      'round-next-song-loading',
      "round: next song loading",
      'H18-NextSongLoading',
      () => round(
        roundView(phase: RoundPhase.loading, playing: false, secondsLeft: 15),
      ),
    ),
    DesignScreen(
      'leaderboard-loading',
      "leaderboard: loading",
      'H20-Loading',
      () => board(state: LeaderboardState.loading),
    ),
    DesignScreen(
      'offline-play-loading',
      "offline play: packs loading",
      null,
      () => OfflinePlayScreen(
        loadingPacks: true,
        wifiOnly: true,
        mobilePrefetch: true,
        cache: mockCache,
        builtInSongCount: mockBuiltInSongCount,
        packs: mockPacks,
        connection: Connection.wifi,
        onBack: _noop,
        onWifiOnly: _noopBool,
        onMobilePrefetch: _noopBool,
        onClearCache: _noop,
        onDownload: _noopString,
        onCancel: _noopString,
        onRetry: _noopString,
        onRemove: _noopString,
      ),
    ),
    DesignScreen(
      'round-clip-playing',
      "round: clip playing",
      'H06-Round',
      () => round(roundView()),
    ),
    DesignScreen(
      'round-clip-ended',
      "round: clip ended, still answering",
      'H06-Round',
      () => round(roundView(playing: false, secondsLeft: 3)),
    ),
    DesignScreen(
      'round-which-era',
      "round: Which Era?",
      'H06-Round',
      () => round(roundView(kind: QuestionKind.era)),
    ),
    DesignScreen(
      'round-correct',
      "round: right",
      'H07-Correct',
      () => round(
        roundView(
          phase: RoundPhase.correct,
          picked: 1,
          points: 143,
          playing: false,
          score: 563,
        ),
      ),
    ),
    DesignScreen(
      'round-correct-with-hint',
      "round: right with the hint",
      'H07-Correct',
      () => round(
        roundView(
          phase: RoundPhase.correct,
          picked: 1,
          points: 72,
          hintUsed: true,
          removed: {0, 3},
        ),
      ),
    ),
    DesignScreen(
      'round-wrong',
      "round: wrong",
      'H08-Wrong',
      () => round(
        roundView(
          phase: RoundPhase.wrong,
          picked: 2,
          playing: false,
          feedbackSeconds: 5,
        ),
      ),
    ),
    DesignScreen(
      'round-wrong-which-era',
      "round: wrong in Which Era?",
      'H08-Wrong',
      () => round(
        roundView(
          phase: RoundPhase.wrong,
          picked: 0,
          kind: QuestionKind.era,
          feedbackSeconds: 4,
        ),
      ),
    ),
    DesignScreen(
      'round-timeout',
      "round: time-out",
      'H08-Wrong',
      () => round(
        roundView(
          phase: RoundPhase.timeout,
          playing: false,
          secondsLeft: 0,
          feedbackSeconds: 5,
        ),
      ),
    ),
    DesignScreen(
      'round-hint-available',
      "round: hint available",
      'H06-Round',
      () => round(roundView(secondsLeft: 12)),
    ),
    DesignScreen(
      'round-hint-applied',
      "round: hint applied",
      'H09-Hint',
      () => round(roundView(hintUsed: true, removed: {0, 2})),
    ),
    DesignScreen(
      'round-hint-sheet',
      "round: hint sheet",
      'H09-Hint',
      () => round(
        roundView(
          overlay: RoundOverlay.hintSheet,
          overlaySeconds: 8,
          paused: true,
        ),
      ),
    ),
    DesignScreen(
      'round-rewarded-ad',
      "round: rewarded ad",
      'H09-Hint',
      () => round(
        roundView(
          overlay: RoundOverlay.rewardedAd,
          overlaySeconds: 3,
          paused: true,
        ),
      ),
    ),
    DesignScreen(
      'round-interstitial-ad',
      "round: ad between rounds",
      null,
      () => round(
        roundView(
          overlay: RoundOverlay.interstitial,
          overlaySeconds: 2,
          phase: RoundPhase.correct,
        ),
      ),
    ),
    DesignScreen(
      'round-leave-dialog',
      "round: leave dialog",
      null,
      () => round(roundView(overlay: RoundOverlay.leaveDialog, paused: true)),
    ),
    DesignScreen(
      'round-paused',
      "round: paused in the background",
      null,
      () => round(roundView(paused: true, playing: false)),
    ),
    DesignScreen(
      'round-resume-notice',
      "round: paused notice with Resume (back from the background or a call)",
      null,
      () => round(
        roundView(overlay: RoundOverlay.paused, paused: true, playing: false),
      ),
    ),
    DesignScreen(
      'results-guest-new-best',
      "results: guest, new best",
      'H10-Results',
      () => results(best: true),
    ),
    DesignScreen(
      'results-signed-in',
      "results: signed in",
      'H10-Results',
      () => results(user: mockSignedIn),
    ),
    DesignScreen(
      'results-saved-offline',
      "results: saved offline",
      'H10-Results',
      () => results(sync: ScoreSync.savedOffline),
    ),
    DesignScreen(
      'results-not-counted',
      "results: not counted",
      'H10-Results',
      () => results(sync: ScoreSync.rejected),
    ),
    DesignScreen(
      'results-synced',
      "results: synced",
      'H10-Results',
      () => results(sync: ScoreSync.synced, user: mockSignedIn),
    ),
    DesignScreen(
      'results-big-score',
      "results: a big score",
      'H10-Results',
      () => results(score: 12480),
    ),
    DesignScreen(
      'leaderboard-guest',
      "leaderboard: guest",
      'H11-Leaderboard',
      () => board(),
    ),
    DesignScreen(
      'leaderboard-signed-in',
      "leaderboard: signed in",
      'H11-Leaderboard',
      () => board(user: mockSignedIn),
    ),
    DesignScreen(
      'leaderboard-not-ranked',
      "leaderboard: signed in, not ranked",
      'H11-Leaderboard',
      () => board(user: mockSignedIn, noRow: true),
    ),
    DesignScreen(
      'leaderboard-all-time-era',
      "leaderboard: all time, one era",
      'H11-Leaderboard',
      () => board(scope: LeaderboardScope.allTime, era: EraId.twoThousands),
    ),
    DesignScreen(
      'leaderboard-empty',
      "leaderboard: empty",
      'H11-Leaderboard',
      () => board(state: LeaderboardState.empty),
    ),
    DesignScreen(
      'leaderboard-offline-saved',
      "leaderboard: offline, saved copy",
      'H11-Leaderboard',
      () => board(state: LeaderboardState.offlineCached, user: mockSignedIn),
    ),
    DesignScreen(
      'leaderboard-offline-none',
      "leaderboard: offline, nothing saved",
      'H11-Leaderboard',
      () => board(state: LeaderboardState.offlineNone),
    ),
    DesignScreen(
      'sign-in-ios',
      "sign in: iOS",
      'H12-SignIn',
      () => sheetOver(
        results(),
        SignInSheet(showApple: true, onProvider: (_) {}, onNotNow: _noop),
      ),
    ),
    DesignScreen(
      'sign-in-android',
      "sign in: Android",
      'H12-SignIn',
      () => sheetOver(
        results(),
        SignInSheet(onProvider: (_) {}, onNotNow: _noop),
      ),
    ),
    DesignScreen(
      'sign-in-signing-in',
      "sign in: signing in",
      'H12-SignIn',
      () => sheetOver(
        results(),
        SignInSheet(
          showApple: true,
          status: SignInStatus.signingIn,
          signingInWith: SignInProvider.apple,
          onProvider: (_) {},
          onNotNow: _noop,
        ),
      ),
    ),
    DesignScreen(
      'sign-in-link-failed',
      "sign in: could not link",
      'H12-SignIn',
      () => sheetOver(
        results(),
        SignInSheet(
          showApple: true,
          status: SignInStatus.linkFailed,
          onProvider: (_) {},
          onNotNow: _noop,
        ),
      ),
    ),
    DesignScreen(
      'email-sign-in',
      "email: sign in",
      'H12-SignIn',
      () => sheetOver(
        results(),
        EmailSignInSheet(
          onSubmit: (_, _) {},
          onForgot: _noop,
          onBack: _noop,
          onToggleCreate: _noop,
        ),
      ),
    ),
    DesignScreen(
      'email-bad-address',
      "email: bad address",
      'H12-SignIn',
      () => sheetOver(
        results(),
        EmailSignInSheet(
          error: EmailError.email,
          onSubmit: (_, _) {},
          onForgot: _noop,
          onBack: _noop,
          onToggleCreate: _noop,
        ),
      ),
    ),
    DesignScreen(
      'email-wrong-password',
      "email: wrong password",
      'H12-SignIn',
      () => sheetOver(
        results(),
        EmailSignInSheet(
          error: EmailError.password,
          onSubmit: (_, _) {},
          onForgot: _noop,
          onBack: _noop,
          onToggleCreate: _noop,
        ),
      ),
    ),
    DesignScreen(
      'email-create-account',
      "email: create an account",
      'H12-SignIn',
      () => sheetOver(
        results(),
        EmailSignInSheet(
          creating: true,
          onSubmit: (_, _) {},
          onForgot: _noop,
          onBack: _noop,
          onToggleCreate: _noop,
        ),
      ),
    ),
    DesignScreen(
      'email-signing-in',
      "email: signing in",
      'H12-SignIn',
      () => sheetOver(
        results(),
        EmailSignInSheet(
          busy: true,
          onSubmit: (_, _) {},
          onForgot: _noop,
          onBack: _noop,
        ),
      ),
    ),
    DesignScreen(
      'display-name',
      "display name",
      null,
      () => sheetOver(results(), DisplayNameSheet(onSave: (_) {})),
    ),
    DesignScreen(
      'display-name-too-short',
      "display name: too short",
      null,
      () => sheetOver(
        results(),
        DisplayNameSheet(
          initialName: 'A',
          error: NameError.tooShort,
          onSave: (_) {},
        ),
      ),
    ),
    DesignScreen(
      'display-name-taken',
      "display name: taken",
      null,
      () => sheetOver(
        results(),
        DisplayNameSheet(
          initialName: 'Selam',
          error: NameError.taken,
          onSave: (_) {},
        ),
      ),
    ),
    DesignScreen(
      'home-guest-online',
      "home, guest online",
      'H03-Home',
      () => home(),
    ),
    DesignScreen(
      'home-first-run',
      "home, first run",
      'H03-Home',
      () => home(user: mockNewGuest),
    ),
    DesignScreen(
      'home-signed-in',
      "home, signed in",
      'H03-Home',
      () => home(user: mockSignedIn),
    ),
    DesignScreen(
      'home-offline-no-packs',
      "home, offline with no packs",
      'H17-OfflineHome',
      () => home(offline: true),
    ),
    DesignScreen(
      'home-offline-with-packs',
      "home, offline with packs",
      'H17-OfflineHome',
      () => home(offline: true, packs: true),
    ),
    DesignScreen(
      'mode-select-intro',
      "mode select, intro",
      'H04-ModeSelect',
      () => modeSelect(GameMode.intro),
    ),
    DesignScreen(
      'mode-select-middle',
      "mode select, middle",
      'H04-ModeSelect',
      () => modeSelect(GameMode.middle),
    ),
    DesignScreen(
      'mode-select-which-era',
      "mode select, which era",
      'H04-ModeSelect',
      () => modeSelect(GameMode.era),
    ),
    DesignScreen('setup', "setup", 'H05-EraSetup', () => setup()),
    DesignScreen(
      'setup-offline-eras-disabled',
      "setup, offline eras disabled",
      'H05-EraSetup',
      () => setup(disabled: {1, 3, 4, 5}),
    ),
    DesignScreen(
      'setup-too-few-songs',
      "setup, too few songs",
      'H05-EraSetup',
      () => setup(tooFew: true),
    ),
    DesignScreen(
      'settings-guest',
      "settings, guest",
      'H13-Settings',
      () => settings(),
    ),
    DesignScreen(
      'settings-signed-in',
      "settings, signed in",
      'H13-Settings',
      () => settings(user: mockSignedIn),
    ),
    DesignScreen(
      'settings-update-badge',
      "settings, update badge",
      'H13-Settings',
      () => settings(update: true),
    ),
    DesignScreen(
      'offline-play-all-states',
      "offline play, all states",
      'H14-OfflinePlay',
      () => offlinePlay(),
    ),
    DesignScreen(
      'offline-play-offline',
      "offline play, offline",
      'H14-OfflinePlay',
      () => offlinePlay(connection: Connection.offline),
    ),
    DesignScreen(
      'offline-play-download-failed',
      "offline play, download failed",
      'H19-DownloadError',
      () => offlinePlay(
        packs: [...mockPacks.take(1), failed(PackProblem.downloadFailed)],
      ),
    ),
    DesignScreen(
      'offline-play-corrupt',
      "offline play, corrupt",
      'H19-DownloadError',
      () => offlinePlay(
        packs: [...mockPacks.take(1), failed(PackProblem.corrupt)],
      ),
    ),
    DesignScreen(
      'offline-play-storage-full',
      "offline play, storage full",
      'H19-DownloadError',
      () => offlinePlay(
        packs: [...mockPacks.take(1), failed(PackProblem.storageFull)],
      ),
    ),
    DesignScreen(
      'offline-play-verifying',
      "offline play, verifying",
      'H14-OfflinePlay',
      () => offlinePlay(
        packs: [
          ...mockPacks.take(1),
          mockPacks[2].copyWith(status: PackStatus.verifying, progress: 1),
        ],
      ),
    ),
  ];
}
