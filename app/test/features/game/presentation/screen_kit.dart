import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yeman_zefen/app.dart';
import 'package:yeman_zefen/features/game/application/session_controller.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/packs/data/pack_service.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';
import 'package:yeman_zefen/features/packs/data/packs_providers.dart';
import 'package:yeman_zefen/features/packs/domain/pack_install_progress.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';

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
      AnswerOption(id: 11, label: 'ዘፈን አንድ\nSong One'),
      AnswerOption(id: 12, label: 'Song Two'),
      AnswerOption(id: 13, label: 'Song Three'),
      AnswerOption(id: 14, label: 'Song Four'),
    ],
    windowMs: 10000,
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

/// A pack service that records installs. [onInstall] can hold one open.
class FakePackService implements PackService {
  final installs = <PackListing>[];
  Future<void> Function(PackListing listing)? onInstall;

  @override
  Future<void> install(PackListing listing) async {
    installs.add(listing);
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
  FakePackService? packService,
  Stream<PackInstallProgress> Function(String slug)? progress,
}) async {
  final router = buildRouter(initialLocation: location);
  final container = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(() => RecordingSessionController(state)),
      bestScoreProvider.overrideWith((ref, key) => (bestScore ?? (_, _) async => null)(key.$1, key.$2)),
      packListingsProvider.overrideWith((ref) async {
        if (packsError != null) throw packsError;
        return packs;
      }),
      installedVersionsProvider.overrideWith((ref) => Stream.value(installed)),
      packServiceProvider.overrideWithValue(packService ?? FakePackService()),
      packInstallProgressProvider.overrideWith((ref, slug) => (progress ?? (_) => const Stream.empty())(slug)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  return Harness(tester, router, container);
}
