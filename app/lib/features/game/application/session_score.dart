import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_db.dart';

/// What the phone knows of a finished session's score on the server.
class SessionScore {
  const SessionScore({this.serverScore, this.queued = false, this.parked = false});

  /// The score the server computed, once it has accepted the session. Null until then.
  final int? serverScore;

  /// The session is still waiting in the upload queue.
  final bool queued;

  /// The server refused the session for good (it cannot be checked), so it does not count.
  final bool parked;
}

/// The server's score for session [id], as the upload queue and the recent sessions show it. It
/// follows both tables, so it changes in place when the server's answer is stored.
final sessionScoreProvider = StreamProvider.autoDispose.family<SessionScore, String>((ref, id) {
  final db = ref.watch(appDbProvider);
  return db
      .customSelect(
        'SELECT r.server_score AS server_score, p.id AS queued, p.parked AS parked '
        'FROM (SELECT 1) '
        'LEFT JOIN recent_sessions r ON r.session_id = ? '
        'LEFT JOIN pending_sessions p ON p.id = ?',
        variables: [Variable.withString(id), Variable.withString(id)],
        readsFrom: {db.recentSessions, db.pendingSessions},
      )
      .watchSingleOrNull()
      .map((row) {
        if (row == null) return const SessionScore();
        return SessionScore(
          serverScore: row.read<int?>('server_score'),
          queued: row.read<String?>('queued') != null,
          parked: row.read<bool?>('parked') ?? false,
        );
      });
});
