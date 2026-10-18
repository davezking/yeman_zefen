import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/l10n/display_name.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';
import 'package:yeman_zefen/features/packs/domain/pack_install_progress.dart';

import 'screen_kit.dart';

// The long-title risk (Phase 4 · Sprint 1). The catalog is not in this repository, so these are
// stress names modelled on the longest titles scraped so far: compound Amharic phrases of 50 to 70
// letters, and Latin spellings of them. Re-run the on-device check against the live catalog once
// the packs are published.
const _longTitle = DisplayName(
  am: 'የማይረሳው የፍቅር ትዝታ በልጅነት ዘመን ያሳለፍናቸው የክረምት ምሽቶች ትዝታ',
  latin: 'Yemayiresaw Yefikir Tizita Belijinet Zemen Yasalefnachew Yekiremit Mishitoch Tizita',
);
const _longArtist = DisplayName(
  am: 'ድምፃዊት ብዙነሽ በቀለ እና የቡድኗ አባላት በሙሉ',
  latin: 'Dimtsawit Bizunesh Bekele Ina Yebudinua Abalat Bemulu',
);

// A small phone, as the narrowest case, at the default size and at the 1.3 text size the spec checks.
const _phone = Size(360, 640);

SessionState _round(RoundPhase phase, {QuestionKind kind = QuestionKind.song, bool wrong = false}) {
  final names = kind == QuestionKind.artist ? _longArtist : _longTitle;
  return playing(
    RoundView(
      number: 10,
      total: 10,
      kind: kind,
      options: [for (var i = 0; i < 4; i++) AnswerOption(id: 11 + i, name: names)],
      windowMs: 10000,
      phase: phase,
      attempt: 1,
      chosenId: phase == RoundPhase.feedback ? 11 : null,
      correctId: phase == RoundPhase.feedback ? (wrong ? 12 : 11) : null,
      points: phase == RoundPhase.feedback && !wrong ? 206 : 0,
    ),
  );
}

SessionState _results() {
  final rounds = [
    for (var i = 1; i <= 10; i++)
      RoundSummary(
        number: i,
        kind: i.isEven ? QuestionKind.artist : QuestionKind.song,
        correctName: i.isEven ? _longArtist : _longTitle,
        chosenName: i % 3 == 0 ? null : (i.isEven ? _longArtist : _longTitle),
        correct: i % 3 == 1,
        points: i % 3 == 1 ? 206 : 0,
        valid: true,
        responseMs: 2500,
      ),
  ];
  const cfg = SessionConfig(mode: GameMode.middle, difficulty: Difficulty.medium, generationId: 4);
  return SessionState(
    phase: SessionPhase.finished,
    config: cfg,
    summary: SessionSummary(
      config: cfg,
      totalScore: 1234,
      rounds: rounds,
      skipped: 2,
      flagged: true,
      bestBefore: 900,
      isNewBest: false,
      saveError: 'database or disk is full',
    ),
  );
}

const _longPack = PackListing(
  slug: 'long',
  nameAm: 'ወርቃማው ዘመን የኢትዮጵያ ሙዚቃ የፍቅርና የትዝታ ዘፈኖች ስብስብ',
  nameEn: 'Golden Era of Ethiopian Music: Love and Nostalgia Songs Collection',
  version: 12,
  manifestUrl: 'u',
  trackCount: 1200,
  totalBytes: 190 * 1024 * 1024,
  publishedAt: 1,
);

void main() {
  for (final language in ['en', 'am']) {
    for (final scale in [1.0, 1.3]) {
      group('$language, text x$scale', () {
        Future<void> pump(
          WidgetTester tester,
          String location, {
          SessionState state = SessionState.idle,
          List<PackListing> packs = const [],
          Map<String, int> installed = const {},
          Stream<PackInstallProgress> Function(String)? progress,
          FakePackService? packService,
        }) async {
          tester.view.physicalSize = _phone;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await pumpScreens(
            tester,
            location: location,
            state: state,
            packs: packs,
            installed: installed,
            progress: progress,
            packService: packService,
            device: Locale(language),
            textScale: scale,
            themed: true,
          );
          await tester.pumpAndSettle();
          // An overflow is a FlutterError in tests; reading it here names the screen that broke.
          expect(tester.takeException(), isNull);
        }

        testWidgets('home', (tester) => pump(tester, '/'));
        testWidgets('setup', (tester) => pump(tester, '/setup'));

        testWidgets('round: song question, long titles', (tester) async {
          await pump(tester, '/play', state: _round(RoundPhase.answering));
          // Long titles can push the last answer below the fold; the list scrolls to it.
          await tester.scrollUntilVisible(find.byKey(const Key('option-14')), 200);
          expect(tester.takeException(), isNull);
        });

        testWidgets('round: artist question, long names', (tester) async {
          await pump(tester, '/play', state: _round(RoundPhase.answering, kind: QuestionKind.artist));
        });

        testWidgets('round: right answer', (tester) => pump(tester, '/play', state: _round(RoundPhase.feedback)));
        testWidgets('round: wrong answer', (tester) => pump(tester, '/play', state: _round(RoundPhase.feedback, wrong: true)));
        testWidgets('round: interrupted', (tester) => pump(tester, '/play', state: _round(RoundPhase.interrupted)));

        testWidgets('results: ten long rows with every note', (tester) async {
          await pump(tester, '/results', state: _results());
          // The list scrolls, so check the rows that are built as well as the ones on screen.
          await tester.scrollUntilVisible(find.byKey(const Key('round-10')), 300);
          expect(tester.takeException(), isNull);
        });

        testWidgets('results: nothing to show', (tester) => pump(tester, '/results'));

        testWidgets('failed start', (tester) async {
          await pump(
            tester,
            '/play',
            state: const SessionState(
              phase: SessionPhase.failed,
              config: config,
              error: SessionError(SessionProblem.tooFewArtists),
            ),
          );
        });

        testWidgets('packs: long names and an install in progress', (tester) async {
          final hold = Completer<void>();
          addTearDown(() => hold.isCompleted ? null : hold.complete());
          await pump(
            tester,
            '/packs',
            packs: [_longPack],
            installed: {'long': 11},
            packService: FakePackService()..onInstall = (_) => hold.future,
            progress: (_) => Stream.value(
              const PackInstallProgress(
                slug: 'long',
                state: PackInstallState.downloading,
                filesDone: 30,
                filesTotal: 240,
                bytesDone: 1,
                bytesTotal: 4,
              ),
            ),
          );
          await tester.tap(find.byType(FilledButton));
          await tester.pump();
          await tester.pump();
          expect(find.byKey(const Key('install-progress')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }
  }
}
