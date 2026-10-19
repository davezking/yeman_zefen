import 'package:flutter/widgets.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/net/network_kind.dart';
import 'package:yeman_zefen/core/l10n/display_name.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'screen_kit.dart';

/// The results with the real game: the phone's count at once, the server's score in its place
/// when it has answered (a session's row in the database changes the screen in place).
void main() {
  testWidgets('shows the total, how many were right, and what was played', (tester) async {
    await pumpScreens(
      tester,
      location: '/results',
      state: finishedState(sessionConfig: const SessionConfig(mode: GameMode.middle, difficulty: Difficulty.hard, generationId: 3)),
    );
    await settle(tester);

    expect(find.text('412'), findsOneWidget);
    expect(find.text('1 of 3 right'), findsOneWidget);
  });

  testWidgets('lists each round with its song, its points, and the right or wrong state', (tester) async {
    await pumpScreens(tester, location: '/results', state: finishedState());
    await settle(tester);

    expect(find.textContaining('Song 1'), findsOneWidget);
    expect(find.text('+206'), findsOneWidget);
    expect(find.textContaining('Song 2'), findsOneWidget);
    expect(find.textContaining('Song 4'), findsNothing, reason: 'a skipped round is not listed');
  });

  testWidgets('says when the score is a new best', (tester) async {
    await pumpScreens(tester, location: '/results', state: finishedState(isNewBest: true));
    await settle(tester);
    expect(find.text('New personal best'), findsOneWidget);
  });

  testWidgets('a wrong Which Era? round names the song, its era, and the era picked', (tester) async {
    const era = SessionConfig(mode: GameMode.generation, difficulty: Difficulty.easy);
    await pumpScreens(
      tester,
      location: '/results',
      state: const SessionState(
        phase: SessionPhase.finished,
        config: era,
        summary: SessionSummary(
          sessionId: 'test-session',
          config: era,
          totalScore: 0,
          rounds: [
            RoundSummary(
              number: 1,
              kind: QuestionKind.era,
              correctName: DisplayName(latin: 'Song 1'),
              chosenName: DisplayName(),
              correctEraId: 3,
              chosenEraId: 5,
              correct: false,
              points: 0,
              valid: true,
              responseMs: 3000,
            ),
          ],
          skipped: 0,
          flagged: false,
          bestBefore: null,
          isNewBest: false,
        ),
      ),
    );
    await settle(tester);
    expect(find.text("Song 1 · The '90s"), findsOneWidget);
  });

  testWidgets('an artist round names the song and its singer, not the singer twice', (tester) async {
    const config = SessionConfig(mode: GameMode.intro, difficulty: Difficulty.medium);
    await pumpScreens(
      tester,
      location: '/results',
      state: const SessionState(
        phase: SessionPhase.finished,
        config: config,
        summary: SessionSummary(
          sessionId: 'test-session',
          config: config,
          totalScore: 0,
          rounds: [
            RoundSummary(
              number: 1,
              kind: QuestionKind.artist,
              correctName: DisplayName(latin: 'Teddy Afro'),
              trackName: DisplayName(latin: 'Tikur Sew'),
              artistName: DisplayName(latin: 'Teddy Afro'),
              chosenName: DisplayName(latin: 'Aster Aweke'),
              correct: false,
              points: 0,
              valid: true,
              responseMs: 3000,
            ),
          ],
          skipped: 0,
          flagged: false,
          bestBefore: null,
          isNewBest: false,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Tikur Sew · Teddy Afro'), findsOneWidget);
  });

  group('the score from the server', () {
    testWidgets('is checked while the phone shows its own count', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState(), auth: _guest);
      await _queue(h);
      await settle(tester);
      expect(find.text('Checking your score…'), findsOneWidget);
      expect(find.text('412'), findsOneWidget);
    });

    testWidgets('is not waited for when the game was not queued (not saved, or taken without a score)', (tester) async {
      await pumpScreens(tester, location: '/results', state: finishedState(), auth: _guest);
      await settle(tester);
      expect(find.text('Checking your score…'), findsNothing);
      expect(find.text('412'), findsOneWidget);
    });

    testWidgets('without an account to send it under, it is saved for later', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState());
      await _queue(h);
      await settle(tester);
      expect(find.text('Checking your score…'), findsNothing);
      expect(find.text("Score saved. It will be sent when you're back online."), findsOneWidget);
    });

    testWidgets('after a failed send while online, it says it will be sent again', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState(), auth: _guest);
      await _queue(h, attempts: 1);
      await settle(tester);
      expect(find.text("Score saved. The server didn't answer, so it will be sent again shortly."), findsOneWidget);
    });

    testWidgets('replaces the phone\'s count in place, and says when they differ', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState());
      await settle(tester);
      expect(find.text('412'), findsOneWidget);

      final db = h.container.read(appDbProvider);
      await db.into(db.recentSessions).insert(
            RecentSessionsCompanion.insert(
              sessionId: 'test-session',
              playedAt: 1,
              trackIdsJson: '[]',
              serverScore: const Value(430),
            ),
          );
      // The database tells the screen after real time; then the count runs up to the new score.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('430'), findsOneWidget);
      expect(find.text('412'), findsNothing);
      expect(find.text('The server counted 430 points. Your phone counted 412.'), findsOneWidget);
    });

    testWidgets('judges "New best" on the server\'s score', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState(bestBefore: 400, isNewBest: true));
      await settle(tester);
      expect(find.text('New personal best'), findsOneWidget);

      final db = h.container.read(appDbProvider);
      await db.into(db.recentSessions).insert(
            RecentSessionsCompanion.insert(
              sessionId: 'test-session',
              playedAt: 1,
              trackIdsJson: '[]',
              serverScore: const Value(390),
            ),
          );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('New personal best'), findsNothing);
    });

    testWidgets('says the score is saved and sent later, while offline', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState(), network: NetworkKind.none);
      await settle(tester);
      final db = h.container.read(appDbProvider);
      await db.into(db.pendingSessions).insert(
            PendingSessionsCompanion.insert(id: 'test-session', payloadJson: '{}', createdAt: 1),
          );
      await settle(tester);
      expect(find.text("Score saved. It will be sent when you're back online."), findsOneWidget);
    });

    testWidgets('says the game was not checked when the server refuses it', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState());
      await settle(tester);
      final db = h.container.read(appDbProvider);
      await db.into(db.pendingSessions).insert(
            PendingSessionsCompanion.insert(id: 'test-session', payloadJson: '{}', createdAt: 1, parked: const Value(true)),
          );
      await settle(tester);
      expect(find.text("This game couldn't be checked, so it won't count toward rankings."), findsOneWidget);
    });
  });

  group('the buttons', () {
    testWidgets('Play again starts the game that was just played', (tester) async {
      const played = SessionConfig(mode: GameMode.middle, difficulty: Difficulty.hard, generationId: 3, rounds: 5);
      final h = await pumpScreens(tester, location: '/results', state: finishedState(sessionConfig: played));
      await settle(tester);
      await tester.tap(find.text('Play again'));
      await settle(tester);
      expect(h.location, '/play');
      expect(h.session.startedWith, played);
      // Leaving the results stops the screen's watch of the database; take the screen down so the
      // stream ends inside the test.
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });

    testWidgets('Change era or mode goes back to setup, and Home to the start', (tester) async {
      final h = await pumpScreens(tester, location: '/results', state: finishedState());
      await settle(tester);
      await tester.tap(find.text('Change era or mode'));
      await settle(tester);
      expect(h.location, '/setup');

      h.router.go('/results');
      await settle(tester);
      await tester.tap(find.text('Home'));
      await settle(tester);
      expect(h.location, '/');
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  });
}

/// Pumps the results; the screen's animations are not waited for.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Signed in anonymously: an account the queue can send under.
const _guest = AuthState(uid: 'guest-uid');

/// Puts the session in the upload queue, as the controller's save does.
Future<void> _queue(Harness h, {int attempts = 0}) {
  final db = h.container.read(appDbProvider);
  return db.into(db.pendingSessions).insert(
        PendingSessionsCompanion.insert(id: 'test-session', payloadJson: '{}', createdAt: 1, attempts: Value(attempts)),
      );
}
