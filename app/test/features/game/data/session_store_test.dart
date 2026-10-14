import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/game/data/session_store.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

import 'session_fixtures.dart';

void main() {
  late AppDb db;
  late SessionStore store;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    store = SessionStore(db);
  });

  tearDown(() => db.close());

  test('stores the payload for upload exactly as built', () async {
    final payload = payloadOf();

    await store.saveCompleted(payload: payload, score: 900, nowMs: 5000);

    final row = await db.select(db.pendingSessions).getSingle();
    expect(row.id, payload.id);
    expect(row.createdAt, 5000);
    expect(row.attempts, 0);
    expect(jsonDecode(row.payloadJson), payload.toJson());
  });

  test('saving the same session twice keeps one payload', () async {
    final payload = payloadOf();
    await store.saveCompleted(payload: payload, score: 900, nowMs: 5000);
    await store.saveCompleted(payload: payload, score: 900, nowMs: 6000);

    expect(await db.select(db.pendingSessions).get(), hasLength(1));
    expect(await db.select(db.recentSessions).get(), hasLength(1));
  });

  group('best score', () {
    test('the first session is a new best', () async {
      final result = await store.saveCompleted(payload: payloadOf(), score: 900, nowMs: 1);
      expect(result.isNewBest, isTrue);
      expect(result.previousBest, isNull);
      expect(await store.bestScore(GameMode.intro, 0), 900);
    });

    test('a first session that scored nothing is not a best', () async {
      final result = await store.saveCompleted(payload: payloadOf(), score: 0, nowMs: 1);
      expect(result.isNewBest, isFalse);
      expect(result.previousBest, isNull);
      expect(await store.bestScore(GameMode.intro, 0), isNull);

      final next = await store.saveCompleted(payload: payloadOf(id: 'b'), score: 50, nowMs: 2);
      expect(next.isNewBest, isTrue);
      expect(await store.bestScore(GameMode.intro, 0), 50);
    });

    test('a lower or equal score does not replace it', () async {
      await store.saveCompleted(payload: payloadOf(id: 'a'), score: 900, nowMs: 1);
      final lower = await store.saveCompleted(payload: payloadOf(id: 'b'), score: 800, nowMs: 2);
      final equal = await store.saveCompleted(payload: payloadOf(id: 'c'), score: 900, nowMs: 3);

      expect(lower.isNewBest, isFalse);
      expect(lower.previousBest, 900);
      expect(equal.isNewBest, isFalse);
      expect(await store.bestScore(GameMode.intro, 0), 900);
    });

    test('a higher score replaces it', () async {
      await store.saveCompleted(payload: payloadOf(id: 'a'), score: 900, nowMs: 1);
      final higher = await store.saveCompleted(payload: payloadOf(id: 'b'), score: 1200, nowMs: 2);

      expect(higher.isNewBest, isTrue);
      expect(higher.previousBest, 900);
      expect(await store.bestScore(GameMode.intro, 0), 1200);
    });

    test('is kept per mode and per era', () async {
      await store.saveCompleted(payload: payloadOf(id: 'a', mode: GameMode.intro), score: 900, nowMs: 1);
      await store.saveCompleted(payload: payloadOf(id: 'b', mode: GameMode.middle), score: 500, nowMs: 2);
      await store.saveCompleted(payload: payloadOf(id: 'c', generationId: 2), score: 300, nowMs: 3);

      expect(await store.bestScore(GameMode.intro, 0), 900);
      expect(await store.bestScore(GameMode.middle, 0), 500);
      expect(await store.bestScore(GameMode.intro, 2), 300);
      expect(await store.bestScore(GameMode.middle, 2), isNull);
    });
  });

  group('recent sessions', () {
    test('are returned newest first', () async {
      await store.saveCompleted(payload: payloadOf(id: 'a', seed: 1), score: 1, nowMs: 100);
      await store.saveCompleted(payload: payloadOf(id: 'b', seed: 2), score: 1, nowMs: 200);

      final recent = await store.recentTrackIds();
      expect(recent, hasLength(2));
      expect(recent.first, payloadOf(id: 'b', seed: 2).rounds.map((r) => r.trackId));
      expect(recent.last, payloadOf(id: 'a', seed: 1).rounds.map((r) => r.trackId));
    });

    test('only the last 3 are kept', () async {
      for (var i = 1; i <= 5; i++) {
        await store.saveCompleted(payload: payloadOf(id: 's$i', seed: i), score: 1, nowMs: i * 100);
      }

      final kept = await db.select(db.recentSessions).get();
      expect(kept.map((r) => r.sessionId).toSet(), {'s3', 's4', 's5'});
      expect(await store.recentTrackIds(), hasLength(3));
      // The payloads waiting for upload are not pruned.
      expect(await db.select(db.pendingSessions).get(), hasLength(5));
    });

    test('are empty before anything was played', () async {
      expect(await store.recentTrackIds(), isEmpty);
    });
  });

  group('clip errors', () {
    test('start at 0 and count up', () async {
      expect(await store.clipErrorCount(), 0);
      await store.addClipError();
      await store.addClipError();
      await store.addClipError();
      expect(await store.clipErrorCount(), 3);
    });
  });
}
