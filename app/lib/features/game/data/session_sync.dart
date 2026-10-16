import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/db/app_db.dart';
import '../../../core/http/api_client.dart';

/// Sends the finished sessions waiting in `pending_sessions` to
/// `POST /v1/sessions`, oldest first among those that are due.
///
/// The server is the source of truth: it computes the score and answers the
/// same way for an `id` it has already stored, so a send that is repeated (a
/// lost response, the app killed between the send and the delete) is safe. A
/// row is deleted only after the server accepted it.
///
/// - One send at a time. A trigger that arrives while a pass runs is not lost:
///   the pass looks again before it ends.
/// - A failed send backs off per session: [baseDelay] doubling each attempt,
///   up to [maxDelay]. Nothing is sent before then, except on a forced pass,
///   and that only skips a wait caused by being offline: a wait the server
///   asked for (a 5xx, a 429 and its Retry-After) still holds.
/// - A 4xx that means the session itself is wrong (400, 409, 413, 422, ...)
///   parks it for good. The row stays with `last_error` for debugging.
/// - Anything that is not the session's fault (offline, a 5xx, 429, a token
///   problem) stops the pass and leaves the rest for the next one.
class SessionSync {
  SessionSync({
    required this.db,
    required this.api,
    required this.auth,
    int Function()? nowMs,
    Timer Function(Duration, void Function())? timer,
    this.baseDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(hours: 1),
  }) : _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
       _timer = timer ?? Timer.new;

  final AppDb db;
  final ApiClient api;

  /// The signed-in player right now. Nothing is sent until there is a uid:
  /// sessions played before the first sign-in wait for it.
  final AuthState Function() auth;

  final Duration baseDelay;
  final Duration maxDelay;

  final int Function() _nowMs;
  final Timer Function(Duration, void Function()) _timer;

  /// A 4xx that says nothing about the session itself: the request timed out.
  /// (401, 403, 404 and 429 have their own exception types and are never parked.)
  static const _transient4xx = {408};

  Completer<void>? _running;
  bool _again = false;
  bool _againForced = false;
  Timer? _wake;
  bool _disposed = false;

  /// The wait after [attempts] failed attempts: 30 s, 1 min, 2 min, ... up to [maxDelay].
  Duration backoff(int attempts) {
    final doublings = min(max(attempts - 1, 0), 20);
    final delay = baseDelay * (1 << doublings);
    return delay > maxDelay ? maxDelay : delay;
  }

  /// Sends what is due. [force] ignores the backoff (the connection came back,
  /// or the app started, so a wait that was about a dead network is over).
  ///
  /// Only one pass runs at a time. A call while one is running returns that
  /// pass's future, and makes it go round again once it finishes. Never throws.
  Future<void> syncNow({bool force = false}) {
    final running = _running;
    if (running != null) {
      _again = true;
      _againForced = _againForced || force;
      return running.future;
    }
    final done = Completer<void>();
    _running = done;
    unawaited(_run(force, done));
    return done.future;
  }

  Future<void> _run(bool force, Completer<void> done) async {
    try {
      var forced = force;
      // Shared by the passes of one run, so a trigger that lands mid-run sends
      // what is new without sending a session that just failed straight again.
      final tried = <String>{};
      do {
        _again = false;
        _againForced = false;
        await _pass(forced, tried);
        await _scheduleWake();
        forced = _againForced;
      } while (_again && !_disposed);
    } catch (e, st) {
      // A database error: the rows are still there for the next pass.
      developer.log('session sync failed', name: 'session_sync', error: e, stackTrace: st);
    } finally {
      // Cleared in the same step as the last check of [_again], so a trigger
      // can never land between "nothing left to do" and "not running".
      _running = null;
      done.complete();
    }
  }

  Future<void> _pass(bool force, Set<String> tried) async {
    while (!_disposed) {
      if (!auth().hasUid) return;
      final row = await _nextDue(tried, force);
      if (row == null) return;
      tried.add(row.id);
      if (!await _send(row)) return;
    }
  }

  /// The oldest session that is not parked, not tried in this run, and due:
  /// its backoff is over, or [force] and it only waits because it was offline.
  ///
  /// A wait that ends more than [maxDelay] from now cannot be one this class
  /// set, so the device clock went back: that session counts as due.
  Future<PendingSession?> _nextDue(Set<String> tried, bool force) {
    final now = _nowMs();
    return (db.select(db.pendingSessions)
          ..where((t) {
            var due = t.nextAttemptAt.isSmallerOrEqualValue(now) |
                t.nextAttemptAt.isBiggerThanValue(now + maxDelay.inMilliseconds);
            if (force) due = due | t.lastStatus.isNull();
            return t.parked.equals(false) & t.id.isNotIn(tried) & due;
          })
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Sends one session. Returns false when the pass should stop.
  Future<bool> _send(PendingSession row) async {
    final Object? body;
    try {
      body = jsonDecode(row.payloadJson);
    } on FormatException catch (e) {
      await _park(row, 'unreadable payload: ${e.message}');
      return true;
    }
    try {
      final response = await api.postJson('/v1/sessions', body: body);
      await _accepted(row, response);
      return true;
    } on RequestException catch (e) {
      final status = e.status!;
      // Only a real 4xx is about the session. The client also reports a
      // redirect or other odd status this way; those are retried.
      if (status < 400 || status >= 500 || _transient4xx.contains(status)) {
        await _backOff(row, e);
        return false;
      }
      await _park(row, '$status ${e.code}: ${e.message}');
      return true;
    } on ApiException catch (e) {
      await _backOff(row, e, retryAfter: e is RateLimitedException ? e.retryAfter : null);
      return false;
    }
  }

  /// The server stored the session. Drop it from the queue and keep the score
  /// it computed next to the session's history entry, in one step: a crash
  /// leaves the row queued (and the next send is a replay), never half done.
  Future<void> _accepted(PendingSession row, Object? response) {
    final score = response is Map<String, dynamic> && response['score'] is int ? response['score'] as int : null;
    return db.transaction(() async {
      await (db.delete(db.pendingSessions)..where((t) => t.id.equals(row.id))).go();
      if (score != null) {
        await (db.update(db.recentSessions)..where((t) => t.sessionId.equals(row.id))).write(
          RecentSessionsCompanion(serverScore: Value(score)),
        );
      }
    });
  }

  Future<void> _park(PendingSession row, String reason) {
    return (db.update(db.pendingSessions)..where((t) => t.id.equals(row.id))).write(
      PendingSessionsCompanion(
        parked: const Value(true),
        attempts: Value(row.attempts + 1),
        lastError: Value(reason),
        lastStatus: const Value(null),
      ),
    );
  }

  Future<void> _backOff(PendingSession row, ApiException error, {Duration? retryAfter}) {
    final attempts = row.attempts + 1;
    var wait = backoff(attempts);
    if (retryAfter != null && retryAfter > wait) wait = retryAfter > maxDelay ? maxDelay : retryAfter;
    return (db.update(db.pendingSessions)..where((t) => t.id.equals(row.id))).write(
      PendingSessionsCompanion(
        attempts: Value(attempts),
        lastError: Value('${error.status ?? 'no response'} ${error.code}: ${error.message}'),
        lastStatus: Value(error.status),
        nextAttemptAt: Value(_nowMs() + wait.inMilliseconds),
      ),
    );
  }

  /// Wakes the sync when the earliest backoff ends, so a lone failed session
  /// is retried even if nothing else happens in the app.
  Future<void> _scheduleWake() async {
    _wake?.cancel();
    _wake = null;
    if (_disposed) return;
    final earliest = db.pendingSessions.nextAttemptAt.min();
    final query = db.selectOnly(db.pendingSessions)
      ..addColumns([earliest])
      ..where(db.pendingSessions.parked.equals(false) & db.pendingSessions.nextAttemptAt.isBiggerThanValue(_nowMs()));
    final next = await query.map((r) => r.read(earliest)).getSingleOrNull();
    if (next == null) return;
    var delay = Duration(milliseconds: next - _nowMs());
    if (delay > maxDelay) delay = maxDelay; // the clock went back
    if (delay < const Duration(seconds: 1)) delay = const Duration(seconds: 1);
    _wake = _timer(delay, () {
      _wake = null;
      unawaited(syncNow());
    });
  }

  void dispose() {
    _disposed = true;
    _wake?.cancel();
    _wake = null;
  }
}
