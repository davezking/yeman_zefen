import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yeman_zefen/app.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/config/remote_config.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/l10n/display_name.dart';
import 'package:yeman_zefen/core/l10n/locale_provider.dart';
import 'package:yeman_zefen/core/theme/app_theme.dart';
import 'package:yeman_zefen/features/account/register_prompt_controller.dart';
import 'package:drift/native.dart';
import 'package:yeman_zefen/core/net/network_kind.dart';
import 'package:yeman_zefen/features/account/data/profile_api.dart';
import 'package:yeman_zefen/features/game/application/play_setup.dart';
import 'package:yeman_zefen/features/game/application/session_controller.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/settings/application/settings_providers.dart';
import 'package:yeman_zefen/features/packs/application/offline_play.dart';
import 'package:yeman_zefen/features/packs/data/pack_service.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';
import 'package:yeman_zefen/features/packs/data/packs_providers.dart';
import 'package:yeman_zefen/features/packs/domain/pack_install_progress.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';

/// A locale store that keeps the choice in memory.
class MemoryLocaleStore implements LocaleStore {
  MemoryLocaleStore([this.saved]);

  Locale? saved;

  @override
  Future<Locale?> read() async => saved;

  @override
  Future<void> write(Locale locale) async => saved = locale;
}

/// Stands in for the session controller. It starts in [initial], records what
/// the screens ask of it, and lets a test move it to another state.
class RecordingSessionController extends SessionController {
  RecordingSessionController(this.initial);

  final SessionState initial;
  SessionConfig? startedWith;
  int? answered;
  var resumed = 0;
  var backgrounded = 0;
  var left = 0;

  @override
  SessionState build() => initial;

  @override
  Future<void> start(SessionConfig config) async => startedWith = config;

  @override
  void answer(int optionId) => answered = optionId;

  @override
  void resume() => resumed++;

  @override
  void pauseForBackground() => backgrounded++;

  @override
  void leave() {
    left++;
    state = SessionState.idle;
  }

  void show(SessionState next) => state = next;
}

const config = SessionConfig(mode: GameMode.intro, difficulty: Difficulty.medium, questions: QuestionMix.song);

RoundView roundView({
  RoundPhase phase = RoundPhase.answering,
  QuestionKind kind = QuestionKind.song,
  int number = 3,
  int total = 10,
  int attempt = 1,
  int? remainingMs,
  int? chosenId,
  int? correctId,
  int? points,
  bool timedOut = false,
  bool valid = true,
}) {
  return RoundView(
    number: number,
    total: total,
    kind: kind,
    options: const [
      AnswerOption(id: 11, name: DisplayName(am: 'ዘፈን አንድ', latin: 'Song One')),
      AnswerOption(id: 12, name: DisplayName(latin: 'Song Two')),
      AnswerOption(id: 13, name: DisplayName(latin: 'Song Three')),
      AnswerOption(id: 14, name: DisplayName(latin: 'Song Four')),
    ],
    windowMs: 10000,
    remainingMs: remainingMs,
    phase: phase,
    attempt: attempt,
    chosenId: chosenId,
    correctId: phase == RoundPhase.feedback ? (correctId ?? 12) : null,
    points: points,
    timedOut: timedOut,
    valid: valid,
  );
}

SessionState playing(RoundView round) => SessionState(phase: SessionPhase.playing, config: config, round: round);

/// A pack service that records installs and their Wi-Fi rule. [onInstall] can hold one open.
class FakePackService implements PackService {
  final installs = <PackListing>[];
  final wifiOnly = <bool>[];
  Future<void> Function(PackListing listing)? onInstall;

  @override
  Future<void> install(PackListing listing, {bool Function()? isCancelled, bool wifiOnly = false}) async {
    installs.add(listing);
    this.wifiOnly.add(wifiOnly);
    await onInstall?.call(listing);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Harness {
  Harness(this.tester, this.router, this.container);

  final WidgetTester tester;
  final GoRouter router;
  final ProviderContainer container;

  RecordingSessionController get session => container.read(sessionControllerProvider.notifier) as RecordingSessionController;

  String get location => router.state.uri.path;
}

/// Pumps the real route table, starting at [location], with the controller
/// replaced by a recording one that starts in [state]. Nothing real is used:
/// no database, no network, no files.
Future<Harness> pumpScreens(
  WidgetTester tester, {
  String location = '/',
  SessionState state = SessionState.idle,
  Future<int?> Function(GameMode mode, int generationId)? bestScore,
  List<PackListing> packs = const [],
  Object? packsError,
  Map<String, int> installed = const {},
  Set<int> eras = const {1, 2, 3, 4, 5},
  AuthState auth = AuthState.signedOut,
  NetworkKind network = NetworkKind.unmetered,
  FakePackService? packService,
  Stream<PackInstallProgress> Function(String slug)? progress,
  Locale device = const Locale('en'),
  double textScale = 1.0,
  bool themed = true,
}) async {
  final router = buildRouter(initialLocation: location);
  final db = AppDb(NativeDatabase.memory());
  addTearDown(db.close);
  final support = Directory.systemTemp.createTempSync('screens');
  addTearDown(() => support.deleteSync(recursive: true));
  final container = ProviderContainer(
    overrides: [
      deviceLocaleProvider.overrideWithBuild((ref, _) => device),
      localeStoreProvider.overrideWithValue(MemoryLocaleStore()),
      sessionControllerProvider.overrideWith(() => RecordingSessionController(state)),
      // The eras with enough songs to play (four each); the all-eras count is their total.
      playableSongsProvider.overrideWith((ref, mode) async => PlayableSongs(
            perEra: {
              0: minPlayableSongsPerEra * eras.length,
              for (final era in eras) era: minPlayableSongsPerEra,
            },
            onDevice: minPlayableSongsPerEra * eras.length,
          )),
      authStateProvider.overrideWith((ref) => Stream.value(auth)),
      ownNameProvider.overrideWith((ref) async => null),
      currentNetworkProvider.overrideWith((ref) => Stream.value(network)),
      appDbProvider.overrideWith((ref) => db),
      supportDirectoryProvider.overrideWith((ref) async => support),
      installedPacksSummaryProvider.overrideWith((ref) => Stream.value(InstalledPacksSummary(count: installed.length, bytes: 0))),
      appVersionProvider.overrideWith((ref) async => '1.0.0'),
      bestScoreProvider.overrideWith((ref, key) => (bestScore ?? (_, _) async => null)(key.$1, key.$2)),
      packListingsProvider.overrideWith((ref) async {
        if (packsError != null) throw packsError;
        return packs;
      }),
      installedVersionsProvider.overrideWith((ref) => Stream.value(installed)),
      // The installed packs, named as the list names them.
      installedPacksProvider.overrideWith(
        (ref) => Stream.value([
          for (final e in installed.entries)
            InstalledPackInfo(
              slug: e.key,
              version: e.value,
              nameAm: packs.where((l) => l.slug == e.key).firstOrNull?.nameAm ?? e.key,
              nameEn: packs.where((l) => l.slug == e.key).firstOrNull?.nameEn ?? e.key,
              songCount: packs.where((l) => l.slug == e.key).firstOrNull?.trackCount ?? 0,
              totalBytes: packs.where((l) => l.slug == e.key).firstOrNull?.totalBytes ?? 0,
            ),
        ]),
      ),
      packServiceProvider.overrideWithValue(packService ?? FakePackService()),
      packInstallProgressProvider.overrideWith((ref, slug) => (progress ?? (_) => const Stream.empty())(slug)),
      // The results route asks for the register prompt. A signed-out device is never asked, so the
      // test never reaches Firebase.
      registerPromptControllerProvider.overrideWith(
        (ref) => RegisterPromptController(
          sessions: ref.watch(sessionStoreProvider),
          db: ref.watch(appDbProvider),
          config: () => RemoteConfig.defaults,
          auth: () => AuthState.signedOut,
          nowMs: () => 0,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // The language follows the locale provider, as in the real app.
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          locale: ref.watch(localeProvider),
          routerConfig: router,
          // As in app.dart: the app theme (fonts and line heights) follows the language, and the
          // player's text size scales everything.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: themed ? Theme(data: buildAppTheme(Localizations.localeOf(context)), child: child!) : child!,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ),
  );
  await tester.pump();
  return Harness(tester, router, container);
}

SessionState finishedState({
  bool unnamed = false,
  int total = 412,
  int? bestBefore,
  bool isNewBest = false,
  int skipped = 0,
  bool flagged = false,
  String? saveError,
  SessionConfig sessionConfig = config,
}) {
  return SessionState(
    phase: SessionPhase.finished,
    config: sessionConfig,
    summary: SessionSummary(
      config: sessionConfig,
      totalScore: total,
      rounds: unnamed
          ? const [
              RoundSummary(
                number: 1, kind: QuestionKind.song, correctName: DisplayName(), chosenName: DisplayName(),
                correct: true, points: 206, valid: true, responseMs: 2500,
              ),
            ]
          : const [
        RoundSummary(
          number: 1, kind: QuestionKind.song,
          correctName: DisplayName(am: 'ዘፈን', latin: 'Song 1'), chosenName: DisplayName(am: 'ዘፈን', latin: 'Song 1'),
          correct: true, points: 206, valid: true, responseMs: 2500,
        ),
        RoundSummary(
          number: 2, kind: QuestionKind.song,
          correctName: DisplayName(latin: 'Song 2'), chosenName: DisplayName(latin: 'Song 9'),
          correct: false, points: 0, valid: true, responseMs: 3100,
        ),
        RoundSummary(
          number: 4, kind: QuestionKind.artist, correctName: DisplayName(latin: 'Artist 3'), chosenName: null,
          correct: false, points: 0, valid: true, responseMs: 10000,
        ),
      ],
      skipped: skipped,
      flagged: flagged,
      bestBefore: bestBefore,
      isNewBest: isNewBest,
      saveError: saveError,
    ),
  );
}
