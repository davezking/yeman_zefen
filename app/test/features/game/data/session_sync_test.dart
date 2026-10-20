import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
import 'package:yeman_zefen/features/game/data/session_sync.dart';

/// A stand-in for POST /v1/sessions that behaves like the real one: it stores a
/// session by id, and a repeated id gets the stored result back.
class FakeServer {
  final stored = <String, int>{};
  final received = <String>[];

  /// Answers to give before behaving normally, one per request. A null entry
  /// means "no network".
  final script = <http.Response?>[];

  /// When set, requests wait for this before answering.
  Completer<void>? gate;

  var inFlight = 0;
  var maxInFlight = 0;

  Future<http.Response> handle(http.Request request) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final id = (jsonDecode(request.body) as Map<String, dynamic>)['id'] as String;
      received.add(id);
      final g = gate;
      if (g != null) await g.future;
      if (script.isNotEmpty) {
        final next = script.removeAt(0);
        if (next == null) throw http.ClientException('no network');
        return next;
      }
      final score = stored.putIfAbsent(id, () => 100 + stored.length);
      return http.Response(jsonEncode({'score': score, 'rounds': [], 'flagged': false}), 200);
    } finally {
      inFlight--;
    }
  }
}

http.Response error(int status, String code, {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode({'error': {'code': code, 'message': 'm'}}), status, headers: headers);

void main() {
  late AppDb db;
  late FakeServer server;
  late int nowMs;
  late AuthState auth;
  late List<(Duration, void Function())> timers;
  late SessionSync sync;

  const signedIn = AuthState(uid: 'u1');

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    server = FakeServer();
    nowMs = 1_000_000;
    auth = signedIn;
    timers = [];
    final client = ApiClient(
      baseUrl: 'https://api.test',
      idToken: ({bool forceRefresh = false}) async => 'token',
      client: MockClient(server.handle),
    );
    sync = SessionSync(
      db: db,
      api: client,
      auth: () => auth,
      nowMs: () => nowMs,
      timer: (d, cb) {
        timers.add((d, cb));
        return Timer(const Duration(days: 1), () {}); // never fires by itself
      },
    );
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
  });

  Future<void> queue(String id, {int? createdAt, String? payload}) async {
    await db.into(db.pendingSessions).insert(
          PendingSessionsCompanion.insert(
            id: id,
            payloadJson: payload ?? jsonEncode({'id': id, 'mode': 'intro'}),
            createdAt: createdAt ?? nowMs,
          ),
        );
    await db.into(db.recentSessions).insertOnConflictUpdate(
          RecentSessionsCompanion.insert(sessionId: id, playedAt: createdAt ?? nowMs, trackIdsJson: '[1]'),
        );
  }

  Future<PendingSession> row(String id) =>
      (db.select(db.pendingSessions)..where((t) => t.id.equals(id))).getSingle();

  Future<List<String>> queued() async => [for (final r in await db.select(db.pendingSessions).get()) r.id];

  Future<int?> serverScore(String id) async =>
      (await (db.select(db.recentSessions)..where((t) => t.sessionId.equals(id))).getSingle()).serverScore;

  test('sends sessions oldest first, deletes them, and keeps the server score', () async {
    await queue('c', createdAt: 3);
    await queue('a', createdAt: 1);
    await queue('b', createdAt: 2);

    await sync.syncNow();

    expect(server.received, ['a', 'b', 'c']);
    expect(await queued(), isEmpty);
    expect(await serverScore('a'), server.stored['a']);
    expect(await serverScore('c'), server.stored['c']);
  });

  test('posts the stored payload as it was saved, with the token', () async {
    final seen = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://api.test',
      idToken: ({bool forceRefresh = false}) async => 'token',
      client: MockClient((r) {
        seen.add(r);
        return server.handle(r);
      }),
    );
    sync = SessionSync(db: db, api: client, auth: () => auth, nowMs: () => nowMs);
    await queue('a', payload: '{"id":"a","mode":"middle","rounds":[1,2]}');

    await sync.syncNow();

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/v1/sessions');
    expect(seen.single.headers['Authorization'], 'Bearer token');
    expect(jsonDecode(seen.single.body), {'id': 'a', 'mode': 'middle', 'rounds': [1, 2]});
  });

  test('a session whose history entry was trimmed away still uploads', () async {
    await queue('a');
    await (db.delete(db.recentSessions)..where((t) => t.sessionId.equals('a'))).go();
    await sync.syncNow();
    expect(await queued(), isEmpty);
  });

  group('offline then online', () {
    test('five sessions played in airplane mode all sync after reconnecting, in order', () async {
      for (var i = 1; i <= 5; i++) {
        await queue('s$i', createdAt: i);
      }
      server.script.add(null);

      await sync.syncNow();
      // Offline: one attempt was enough to see that, and nothing was lost.
      expect(server.received, ['s1']);
      expect(await queued(), ['s1', 's2', 's3', 's4', 's5']);
      expect((await row('s1')).attempts, 1);
      expect((await row('s1')).lastError, contains('network_error'));
      expect((await row('s2')).attempts, 0);

      // Back online: the connection-regained trigger ignores the backoff.
      server.received.clear();
      await sync.syncNow(force: true);
      expect(server.received, ['s1', 's2', 's3', 's4', 's5']);
      expect(await queued(), isEmpty);
    });

    test('without a uid nothing is sent; once signed in the waiting sessions go', () async {
      auth = AuthState.signedOut;
      await queue('a');
      await sync.syncNow(force: true);
      expect(server.received, isEmpty);
      expect(await queued(), ['a']);
      expect((await row('a')).attempts, 0);

      auth = signedIn;
      await sync.syncNow(force: true);
      expect(server.received, ['a']);
      expect(await queued(), isEmpty);
    });
  });

  group('failures that are worth retrying', () {
    test('a 500 backs off, then the next attempt succeeds and removes the row', () async {
      await queue('a');
      server.script.add(error(500, 'internal'));

      await sync.syncNow();
      var r = await row('a');
      expect(r.attempts, 1);
      expect(r.parked, isFalse);
      expect(r.lastError, contains('internal'));
      expect(r.nextAttemptAt, nowMs + 30000);

      // Still waiting: a trigger that respects the backoff sends nothing.
      server.received.clear();
      nowMs += 29000;
      await sync.syncNow();
      expect(server.received, isEmpty);

      nowMs += 1000;
      await sync.syncNow();
      expect(server.received, ['a']);
      expect(await queued(), isEmpty);
    });

    test('a forced pass skips a wait caused by being offline', () async {
      await queue('a');
      server.script.add(null);
      await sync.syncNow();
      expect((await row('a')).lastStatus, isNull);
      server.received.clear();
      await sync.syncNow(force: true);
      expect(server.received, ['a']);
      expect(await queued(), isEmpty);
    });

    test('a forced pass keeps a wait the server asked for (5xx), and sends the rest', () async {
      await queue('busy', createdAt: 1);
      await queue('fresh', createdAt: 2);
      server.script.add(error(503, 'unavailable'));
      await sync.syncNow();
      expect((await row('busy')).lastStatus, 503);

      // App start: the sign-in and the first connectivity event both force a pass.
      server.received.clear();
      await Future.wait([sync.syncNow(force: true), sync.syncNow(force: true)]);
      expect(server.received, ['fresh']);
      expect(await queued(), ['busy']);
    });

    test('a 429 holds the whole queue until Retry-After is over, even for a forced pass', () async {
      for (var i = 1; i <= 15; i++) {
        await queue('s${i.toString().padLeft(2, '0')}', createdAt: i);
      }
      // The server lets 5 through, then asks the player to wait ten minutes.
      for (var i = 0; i < 5; i++) {
        server.script.add(http.Response(jsonEncode({'score': 1, 'rounds': [], 'flagged': false}), 200));
      }
      server.script.add(error(429, 'rate_limited', headers: {'retry-after': '600'}));
      await sync.syncNow();
      expect(server.received, ['s01', 's02', 's03', 's04', 's05', 's06']);
      expect((await row('s06')).lastStatus, 429);
      expect((await row('s06')).nextAttemptAt, nowMs + 600000);
      expect(timers.last.$1, const Duration(seconds: 600));

      // The connection comes back, the app starts, a new session is played: nothing goes out.
      server.received.clear();
      await Future.wait([sync.syncNow(force: true), sync.syncNow()]);
      nowMs += 599000;
      await sync.syncNow(force: true);
      expect(server.received, isEmpty);

      // Retry-After is over: the queue drains, oldest first, and nothing is lost.
      nowMs += 1000;
      await sync.syncNow();
      expect(server.received, [for (var i = 6; i <= 15; i++) 's${i.toString().padLeft(2, '0')}']);
      expect(await queued(), isEmpty);
    });

    test('a session tried once in a run is not sent again by a trigger landing mid-run', () async {
      await queue('a', createdAt: 1);
      await queue('b', createdAt: 2);
      server.gate = Completer<void>();
      server.script.add(null); // 'a' fails for want of a connection

      final first = sync.syncNow(force: true);
      await pumpEventQueue();
      final second = sync.syncNow(force: true);
      server.gate!.complete();
      await Future.wait([first, second]);

      // The re-run sends 'b' but does not retry 'a' straight away.
      expect(server.received, ['a', 'b']);
      expect(await queued(), ['a']);
    });

    test('a redirect or other non-4xx status is retried, not parked', () async {
      await queue('a');
      server.script.add(http.Response('', 307));
      await sync.syncNow();
      final r = await row('a');
      expect(r.parked, isFalse);
      expect(r.lastStatus, 307);
      expect(r.attempts, 1);
    });

    test('a wait that ends further away than the longest backoff counts as due (the clock went back)', () async {
      await queue('a');
      await (db.update(db.pendingSessions)..where((t) => t.id.equals('a'))).write(
        PendingSessionsCompanion(nextAttemptAt: Value(nowMs + 86400000), attempts: const Value(3), lastStatus: const Value(500)),
      );
      await sync.syncNow();
      expect(server.received, ['a']);
    });

    test('the wake-up never waits longer than the longest backoff', () async {
      await queue('a');
      await (db.update(db.pendingSessions)..where((t) => t.id.equals('a'))).write(
        PendingSessionsCompanion(nextAttemptAt: Value(nowMs + 86400000), attempts: const Value(3), lastStatus: const Value(500)),
      );
      await queue('b');
      server.script.add(error(500, 'internal'));
      // 'a' is due (clock went back) and fails again; its new wait is normal.
      await sync.syncNow();
      expect(timers.last.$1 <= const Duration(hours: 1), isTrue);
    });

    test('the wait doubles with each failure and stops at an hour', () {
      expect([for (var n = 1; n <= 9; n++) sync.backoff(n).inSeconds], [30, 60, 120, 240, 480, 960, 1920, 3600, 3600]);
      expect(sync.backoff(500), const Duration(hours: 1));
    });

    test('repeated failures lengthen the wait', () async {
      await queue('a');
      for (var i = 0; i < 3; i++) {
        server.script.add(error(500, 'internal'));
        nowMs += 3600 * 1000;
        await sync.syncNow();
      }
      final r = await row('a');
      expect(r.attempts, 3);
      expect(r.nextAttemptAt, nowMs + 120000);
    });

    test('a failure stops the pass, so the other sessions are not tried against a down server', () async {
      await queue('a', createdAt: 1);
      await queue('b', createdAt: 2);
      server.script.add(error(500, 'internal'));
      await sync.syncNow();
      expect(server.received, ['a']);
      expect((await row('b')).attempts, 0);
    });

    test('a 429 waits at least as long as Retry-After says', () async {
      await queue('a');
      server.script.add(error(429, 'rate_limited', headers: {'retry-after': '600'}));
      await sync.syncNow();
      expect((await row('a')).nextAttemptAt, nowMs + 600000);
      expect((await row('a')).parked, isFalse);
    });

    test('a token problem (401) is retried later, not parked', () async {
      await queue('a');
      server.script.addAll([error(401, 'unauthorized'), error(401, 'unauthorized')]);
      await sync.syncNow();
      expect((await row('a')).parked, isFalse);
      expect((await row('a')).attempts, 1);
    });

    test('schedules a wake-up for when the earliest backoff ends, and it sends the session', () async {
      await queue('a');
      server.script.add(error(500, 'internal'));
      await sync.syncNow();
      expect(timers.last.$1, const Duration(seconds: 30));

      nowMs += 30000;
      server.received.clear();
      timers.last.$2();
      await pumpEventQueue();
      expect(server.received, ['a']);
      expect(await queued(), isEmpty);
    });
  });

  group('failures that park a session for good', () {
    for (final (status, code) in [(422, 'invalid_session'), (400, 'validation_error'), (409, 'session_conflict'), (413, 'payload_too_large')]) {
      test('a $status is parked with its reason and never sent again', () async {
        await queue('bad', createdAt: 1);
        await queue('good', createdAt: 2);
        server.script.add(error(status, code));

        await sync.syncNow();
        final r = await row('bad');
        expect(r.parked, isTrue);
        expect(r.lastError, contains('$status'));
        expect(r.lastError, contains(code));
        // The rest of the queue is not held up by it.
        expect(await queued(), ['bad']);
        expect(server.stored.keys, ['good']);

        server.received.clear();
        await sync.syncNow(force: true);
        expect(server.received, isEmpty);
        expect(await queued(), ['bad']);
      });
    }

    test('a payload that is not JSON is parked without a request', () async {
      await queue('junk', payload: '{nope');
      await sync.syncNow();
      expect(server.received, isEmpty);
      expect((await row('junk')).parked, isTrue);
      expect((await row('junk')).lastError, contains('unreadable payload'));
    });
  });

  group('sending twice', () {
    test('a session the server already stored (the app died before deleting the row) is not counted again', () async {
      await queue('a');
      server.stored['a'] = 286; // an earlier send reached the server

      await sync.syncNow();
      expect(server.stored, {'a': 286});
      expect(await queued(), isEmpty);
      expect(await serverScore('a'), 286);

      // Even a second row for the same session (the same id cannot be saved twice) changes nothing.
      await queue('a');
      await sync.syncNow();
      expect(server.stored, {'a': 286});
    });

    test('a crash between the upload and the delete leaves the row, and the retry is a replay', () async {
      await queue('a');
      var crash = true;
      final client = ApiClient(
        baseUrl: 'https://api.test',
        idToken: ({bool forceRefresh = false}) async => 'token',
        client: MockClient((r) async {
          final res = await server.handle(r);
          if (crash) {
            crash = false;
            // The response never reached the app.
            throw http.ClientException('connection lost');
          }
          return res;
        }),
      );
      sync = SessionSync(db: db, api: client, auth: () => auth, nowMs: () => nowMs);

      await sync.syncNow();
      expect(await queued(), ['a']);
      expect(server.stored.length, 1);

      await sync.syncNow(force: true);
      expect(await queued(), isEmpty);
      expect(server.stored.length, 1);
      expect(server.received, ['a', 'a']);
    });
  });

  group('one at a time', () {
    test('overlapping calls share one pass and never send in parallel', () async {
      for (var i = 1; i <= 3; i++) {
        await queue('s$i', createdAt: i);
      }
      await Future.wait([sync.syncNow(), sync.syncNow(), sync.syncNow(force: true)]);
      expect(server.maxInFlight, 1);
      expect(server.received, ['s1', 's2', 's3']);
    });

    test('a session finished while a pass is running is sent by that pass', () async {
      await queue('first', createdAt: 1);
      server.gate = Completer<void>();

      final pass = sync.syncNow();
      await pumpEventQueue();
      expect(server.received, ['first']);

      // The player finishes another session; its trigger arrives mid-pass.
      await queue('second', createdAt: 2);
      final second = sync.syncNow();

      server.gate!.complete();
      await Future.wait([pass, second]);

      expect(server.received, ['first', 'second']);
      expect(server.maxInFlight, 1);
      expect(await queued(), isEmpty);
    });

    test('a forced trigger that arrives mid-pass is not lost (the connection came back during a send)', () async {
      await queue('due', createdAt: 1);
      await queue('waiting', createdAt: 2);
      await (db.update(db.pendingSessions)..where((t) => t.id.equals('waiting'))).write(
        PendingSessionsCompanion(nextAttemptAt: Value(nowMs + 600000), attempts: const Value(2)),
      );
      server.gate = Completer<void>();

      final pass = sync.syncNow();
      await pumpEventQueue();
      final forced = sync.syncNow(force: true);
      server.gate!.complete();
      await Future.wait([pass, forced]);

      expect(server.received, ['due', 'waiting']);
      expect(await queued(), isEmpty);
    });

    test('a pass can run again after the last one finished', () async {
      await queue('a');
      await sync.syncNow();
      await queue('b');
      await sync.syncNow();
      expect(server.received, ['a', 'b']);
    });
  });

  test('never throws, even when the database is gone', () async {
    await queue('a');
    await db.close();
    await sync.syncNow();
    // Re-open for tearDown.
    db = AppDb(NativeDatabase.memory());
  });
}
