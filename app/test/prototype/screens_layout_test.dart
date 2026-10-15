import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/prototype/mock_data.dart';
import 'package:yeman_zefen/prototype/models.dart';
import 'package:yeman_zefen/prototype/screens/home_screen.dart';
import 'package:yeman_zefen/prototype/screens/mode_select_screen.dart';
import 'package:yeman_zefen/prototype/screens/offline_play_screen.dart';
import 'package:yeman_zefen/prototype/screens/settings_screen.dart';
import 'package:yeman_zefen/prototype/screens/setup_screen.dart';

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

  final screens = <String, Widget Function()>{
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
