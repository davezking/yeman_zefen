import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/db/app_db.dart';
import '../../../core/http/api_client.dart';
import 'clip_store.dart';

/// Why a clip would not play, as `POST /v1/reports/clip` names it.
enum ClipFailure {
  /// The clip was on the device, but its file was gone.
  fileMissing('file_missing'),

  /// The player could not load or start it.
  decodeError('decode_error'),

  /// It decoded to under a second of audio.
  tooShort('too_short');

  const ClipFailure(this.wireName);
  final String wireName;
}

/// Takes a clip that would not play out of the game and tells the admins about it.
///
/// [report] marks the clip broken (see [ClipStore.markBroken]) and queues one report for it in
/// `pending_clip_reports`; [flush] sends the queue. A report stays queued while the API cannot be
/// reached, so a clip that broke offline is reported once the phone is back online. One report
/// per clip is queued: a second failure of the same clip before the first is sent adds nothing.
class ClipReporter {
  ClipReporter({required this.db, required this.store, required this.api, int Function()? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDb db;
  final ClipStore store;
  final ApiClient api;
  final int Function() _nowMs;

  Future<void>? _flushing;

  /// Marks the clip broken and queues its report, then sends the queue in the background. Never
  /// throws: a report must not stop a game.
  Future<void> report(int trackId, ClipKind kind, ClipFailure failure) async {
    try {
      await store.markBroken(trackId, kind);
      await db.into(db.pendingClipReports).insert(
            PendingClipReportsCompanion.insert(
              trackId: trackId,
              kind: kind.name,
              error: failure.wireName,
              createdAt: _nowMs(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } catch (_) {
      // The clip plays again next time, and fails again, which reports it then.
      return;
    }
    unawaited(flush());
  }

  /// Sends the queued reports, oldest first. One that the API refused for good (a 4xx other than
  /// 401, including the daily limit) is dropped; on anything else the rest wait for the next call.
  Future<void> flush() => _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    try {
      final rows = await (db.select(db.pendingClipReports)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
      for (final row in rows) {
        try {
          await api.postJson(
            '/v1/reports/clip',
            body: {'trackId': row.trackId, 'clipType': row.kind, 'error': row.error},
          );
        } on ApiException catch (e) {
          final status = e.status;
          // Offline, a server error, or no signed-in player yet: try again later.
          if (status == null || status == 401 || status >= 500) return;
        }
        await (db.delete(db.pendingClipReports)
              ..where((t) => t.trackId.equals(row.trackId) & t.kind.equals(row.kind)))
            .go();
      }
    } catch (_) {
      // The queue stays for the next start.
    }
  }
}
