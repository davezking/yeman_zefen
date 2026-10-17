import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/app_db.dart';
import '../domain/round_generator.dart';
import '../domain/session_config.dart';
import '../domain/session_payload.dart';

class SessionSaveResult {
  const SessionSaveResult({required this.previousBest, required this.isNewBest});

  /// The best score for this mode and era before the session, or null if none.
  final int? previousBest;
  final bool isNewBest;
}

/// What the app keeps on the device about played sessions: the payloads waiting
/// to be sent, the best score per mode and era, the last sessions' tracks, and
/// how many rounds were skipped for a bad clip.
class SessionStore {
  SessionStore(this.db);

  final AppDb db;

  final _saved = StreamController<void>.broadcast();

  /// Fires after each finished session is saved, so the upload can start right away.
  Stream<void> get saved => _saved.stream;

  void dispose() => _saved.close();

  static const clipErrorsCounter = 'clip_errors';
  static const completedSessionsCounter = 'completed_sessions';

  /// The track ids of the last sessions, newest first.
  Future<List<List<int>>> recentTrackIds() async {
    final rows = await (db.select(db.recentSessions)
          ..orderBy([(t) => OrderingTerm.desc(t.playedAt)])
          ..limit(RoundGenerator.historySessions))
        .get();
    return [
      for (final r in rows) [for (final id in jsonDecode(r.trackIdsJson) as List<dynamic>) id as int],
    ];
  }

  Future<int?> bestScore(GameMode mode, int generationId) async {
    final row = await (db.select(db.localBests)
          ..where((t) => t.mode.equals(mode.name) & t.generationId.equals(generationId)))
        .getSingleOrNull();
    return row?.bestScore;
  }

  Future<int> clipErrorCount() async {
    final row = await (db.select(db.localCounters)..where((t) => t.name.equals(clipErrorsCounter))).getSingleOrNull();
    return row?.count ?? 0;
  }

  /// How many sessions have been finished on this device, kept for good (the saved payloads are
  /// emptied once uploaded). Drives the register prompt.
  Future<int> completedSessionCount() async {
    final row = await (db.select(db.localCounters)..where((t) => t.name.equals(completedSessionsCounter)))
        .getSingleOrNull();
    return row?.count ?? 0;
  }

  Future<void> addClipError() {
    return db.customStatement(
      'INSERT INTO local_counters (name, count) VALUES (?, 1) '
      'ON CONFLICT(name) DO UPDATE SET count = count + 1',
      [clipErrorsCounter],
    );
  }

  /// Saves a finished session: its payload for upload, its score as the best if
  /// it beats the old one, and its tracks as history. All or nothing.
  Future<SessionSaveResult> saveCompleted({
    required SessionPayload payload,
    required int score,
    required int nowMs,
  }) async {
    final result = await db.transaction(() async {
      await db.into(db.pendingSessions).insert(
            PendingSessionsCompanion.insert(
              id: payload.id,
              payloadJson: jsonEncode(payload.toJson()),
              createdAt: nowMs,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      // Counted only when the row above went in, so saving the same session again counts it once.
      // `changes()` is the insert's: nothing writes in between.
      await db.customStatement(
        'INSERT INTO local_counters (name, count) SELECT ?, 1 WHERE changes() > 0 '
        'ON CONFLICT(name) DO UPDATE SET count = count + 1',
        [completedSessionsCounter],
      );

      final previous = await bestScore(payload.mode, payload.generationId);
      // A first session that scored nothing is not a best worth showing.
      final isNewBest = score > (previous ?? 0);
      if (isNewBest) {
        await db.into(db.localBests).insertOnConflictUpdate(
              LocalBestsCompanion.insert(
                mode: payload.mode.name,
                generationId: payload.generationId,
                bestScore: score,
                achievedAt: nowMs,
              ),
            );
      }

      await db.into(db.recentSessions).insertOnConflictUpdate(
            RecentSessionsCompanion.insert(
              sessionId: payload.id,
              playedAt: nowMs,
              trackIdsJson: jsonEncode([for (final r in payload.rounds) r.trackId]),
            ),
          );
      await db.customStatement(
        'DELETE FROM recent_sessions WHERE session_id NOT IN '
        '(SELECT session_id FROM recent_sessions ORDER BY played_at DESC LIMIT ?)',
        [RoundGenerator.historySessions],
      );

      return SessionSaveResult(previousBest: previous, isNewBest: isNewBest);
    });
    _saved.add(null);
    return result;
  }
}
