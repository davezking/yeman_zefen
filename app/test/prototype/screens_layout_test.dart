import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/prototype/mock_data.dart';
import 'package:yeman_zefen/prototype/models.dart';
import 'package:yeman_zefen/prototype/screens/home_screen.dart';
import 'package:yeman_zefen/prototype/screens/leaderboard_screen.dart';
import 'package:yeman_zefen/prototype/screens/mode_select_screen.dart';
import 'package:yeman_zefen/prototype/screens/offline_play_screen.dart';
import 'package:yeman_zefen/prototype/screens/results_screen.dart';
import 'package:yeman_zefen/prototype/screens/round_screen.dart';
import 'package:yeman_zefen/prototype/screens/settings_screen.dart';
import 'package:yeman_zefen/prototype/screens/setup_screen.dart';
import 'package:yeman_zefen/prototype/screens/sign_in_sheet.dart';

import 'screen_kit.dart';

void _noop() {}
void _noopString(String _) {}
void _noopBool(bool _) {}

/// Every screen, in every variant, in both languages at text scale 1.0 and 1.3
/// on a 360 dp wide phone. The only assertion is that nothing overflows or
/// throws: the matching with the approved boards is checked by eye.
void main() {
  setUpAll(loadAppFonts);

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

  final rows = [
    for (var i = 0; i < 10; i++)
      RoundResult(
        track: mockTracks[(i * 7) % mockTracks.length],
        correct: i % 4 != 2,
        points: i % 4 != 2 ? 143 - i : 0,
        timedOut: i == 6,
      ),
  ];

  Widget results({
    UserInfo user = mockGuest,
    bool best = false,
    ScoreSync sync = ScoreSync.provisional,
    int score = 1240,
  }) => ResultsScreen(
    view: ResultsView(
      score: score,
      rounds: rows,
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
      me: user.isGuest || noRow ? null : mockMyEntry(scope, era),
      state: state,
      cachedAt: '3:20 PM',
    ),
    onBack: _noop,
    onScope: (_) {},
    onEra: (_) {},
    onSignIn: _noop,
  );

  // ---- the sign-in sheets, as they sit over a screen ----

  Widget sheet(Widget content) => Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: AppSheet(child: content),
    ),
  );

  final screens = <String, Widget Function()>{
    'round: clip playing': () => round(roundView()),
    'round: clip ended, still answering': () =>
        round(roundView(playing: false, secondsLeft: 3)),
    'round: Which Era?': () => round(roundView(kind: QuestionKind.era)),
    'round: right': () => round(
      roundView(
        phase: RoundPhase.correct,
        picked: 1,
        points: 143,
        playing: false,
        score: 563,
      ),
    ),
    'round: right with the hint': () => round(
      roundView(
        phase: RoundPhase.correct,
        picked: 1,
        points: 72,
        hintUsed: true,
        removed: {0, 3},
      ),
    ),
    'round: wrong': () => round(
      roundView(
        phase: RoundPhase.wrong,
        picked: 2,
        playing: false,
        feedbackSeconds: 5,
      ),
    ),
    'round: wrong in Which Era?': () => round(
      roundView(
        phase: RoundPhase.wrong,
        picked: 0,
        kind: QuestionKind.era,
        feedbackSeconds: 4,
      ),
    ),
    'round: time-out': () => round(
      roundView(
        phase: RoundPhase.timeout,
        playing: false,
        secondsLeft: 0,
        feedbackSeconds: 5,
      ),
    ),
    'round: hint available': () => round(roundView(secondsLeft: 12)),
    'round: hint applied': () =>
        round(roundView(hintUsed: true, removed: {0, 2})),
    'round: hint sheet': () => round(
      roundView(
        overlay: RoundOverlay.hintSheet,
        overlaySeconds: 8,
        paused: true,
      ),
    ),
    'round: rewarded ad': () => round(
      roundView(
        overlay: RoundOverlay.rewardedAd,
        overlaySeconds: 3,
        paused: true,
      ),
    ),
    'round: ad between rounds': () => round(
      roundView(
        overlay: RoundOverlay.interstitial,
        overlaySeconds: 2,
        phase: RoundPhase.correct,
      ),
    ),
    'round: leave dialog': () =>
        round(roundView(overlay: RoundOverlay.leaveDialog, paused: true)),
    'round: paused in the background': () =>
        round(roundView(paused: true, playing: false)),
    'results: guest, new best': () => results(best: true),
    'results: signed in': () => results(user: mockSignedIn),
    'results: saved offline': () => results(sync: ScoreSync.savedOffline),
    'results: not counted': () => results(sync: ScoreSync.rejected),
    'results: synced': () =>
        results(sync: ScoreSync.synced, user: mockSignedIn),
    'results: a big score': () => results(score: 12480),
    'leaderboard: guest': () => board(),
    'leaderboard: signed in': () => board(user: mockSignedIn),
    'leaderboard: signed in, not ranked': () =>
        board(user: mockSignedIn, noRow: true),
    'leaderboard: all time, one era': () =>
        board(scope: LeaderboardScope.allTime, era: EraId.twoThousands),
    'leaderboard: empty': () => board(state: LeaderboardState.empty),
    'leaderboard: offline, saved copy': () =>
        board(state: LeaderboardState.offlineCached, user: mockSignedIn),
    'leaderboard: offline, nothing saved': () =>
        board(state: LeaderboardState.offlineNone),
    'sign in: iOS': () => sheet(
      SignInSheet(showApple: true, onProvider: (_) {}, onNotNow: _noop),
    ),
    'sign in: Android': () =>
        sheet(SignInSheet(onProvider: (_) {}, onNotNow: _noop)),
    'sign in: signing in': () => sheet(
      SignInSheet(
        showApple: true,
        status: SignInStatus.signingIn,
        signingInWith: SignInProvider.apple,
        onProvider: (_) {},
        onNotNow: _noop,
      ),
    ),
    'sign in: could not link': () => sheet(
      SignInSheet(
        showApple: true,
        status: SignInStatus.linkFailed,
        onProvider: (_) {},
        onNotNow: _noop,
      ),
    ),
    'email: sign in': () => sheet(
      EmailSignInSheet(
        onSubmit: (_, _) {},
        onForgot: _noop,
        onBack: _noop,
        onToggleCreate: _noop,
      ),
    ),
    'email: bad address': () => sheet(
      EmailSignInSheet(
        error: EmailError.email,
        onSubmit: (_, _) {},
        onForgot: _noop,
        onBack: _noop,
        onToggleCreate: _noop,
      ),
    ),
    'email: wrong password': () => sheet(
      EmailSignInSheet(
        error: EmailError.password,
        onSubmit: (_, _) {},
        onForgot: _noop,
        onBack: _noop,
        onToggleCreate: _noop,
      ),
    ),
    'email: create an account': () => sheet(
      EmailSignInSheet(
        creating: true,
        onSubmit: (_, _) {},
        onForgot: _noop,
        onBack: _noop,
        onToggleCreate: _noop,
      ),
    ),
    'email: signing in': () => sheet(
      EmailSignInSheet(
        busy: true,
        onSubmit: (_, _) {},
        onForgot: _noop,
        onBack: _noop,
      ),
    ),
    'display name': () => sheet(DisplayNameSheet(onSave: (_) {})),
    'display name: too short': () => sheet(
      DisplayNameSheet(
        initialName: 'A',
        error: NameError.tooShort,
        onSave: (_) {},
      ),
    ),
    'display name: taken': () => sheet(
      DisplayNameSheet(
        initialName: 'Selam',
        error: NameError.taken,
        onSave: (_) {},
      ),
    ),

    'home, guest online': () => home(),
    'home, first run': () => home(user: mockNewGuest),
    'home, signed in': () => home(user: mockSignedIn),
    'home, offline with no packs': () => home(offline: true),
    'home, offline with packs': () => home(offline: true, packs: true),
    'mode select, intro': () => modeSelect(GameMode.intro),
    'mode select, middle': () => modeSelect(GameMode.middle),
    'mode select, which era': () => modeSelect(GameMode.era),
    'setup': () => setup(),
    'setup, offline eras disabled': () => setup(disabled: {1, 3, 4, 5}),
    'setup, too few songs': () => setup(tooFew: true),
    'settings, guest': () => settings(),
    'settings, signed in': () => settings(user: mockSignedIn),
    'settings, update badge': () => settings(update: true),
    'offline play, all states': () => offlinePlay(),
    'offline play, offline': () => offlinePlay(connection: Connection.offline),
    'offline play, download failed': () => offlinePlay(
      packs: [...mockPacks.take(1), failed(PackProblem.downloadFailed)],
    ),
    'offline play, corrupt': () =>
        offlinePlay(packs: [...mockPacks.take(1), failed(PackProblem.corrupt)]),
    'offline play, storage full': () => offlinePlay(
      packs: [...mockPacks.take(1), failed(PackProblem.storageFull)],
    ),
    'offline play, verifying': () => offlinePlay(
      packs: [
        ...mockPacks.take(1),
        mockPacks[2].copyWith(status: PackStatus.verifying, progress: 1),
      ],
    ),
  };

  for (final entry in screens.entries) {
    for (final locale in languages) {
      for (final scale in textScales) {
        testWidgets('${entry.key} fits, ${locale.languageCode}, text x$scale', (
          tester,
        ) async {
          await pumpScreen(
            tester,
            entry.value(),
            locale: locale,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
