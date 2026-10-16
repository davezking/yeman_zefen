import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'app_db.g.dart';

/// Packs the app has downloaded and verified. `manifestJson` is the full manifest,
/// kept so clip URLs and checksums stay available offline.
class InstalledPacks extends Table {
  TextColumn get slug => text()();
  IntColumn get version => integer()();
  TextColumn get manifestJson => text()();
  IntColumn get installedAt => integer()(); // epoch ms, UTC
  IntColumn get totalBytes => integer()();

  @override
  Set<Column> get primaryKey => {slug};
}

/// Tracks from installed packs, with the display fields from the manifest and the
/// local clip paths. A track can appear in more than one pack, so the key is per pack.
class LocalTracks extends Table {
  TextColumn get packSlug => text()();
  IntColumn get id => integer()();
  TextColumn get titleAm => text().nullable()();
  TextColumn get titleLatin => text().nullable()();
  TextColumn get artistAm => text().nullable()();
  TextColumn get artistLatin => text().nullable()();

  /// The artist's catalog id and the track's era (generation). The round engine
  /// needs both to build same-era and distinct-artist options. Nullable because
  /// rows written before schema 2 do not have them, and an era can be unknown.
  IntColumn get artistId => integer().nullable()();
  IntColumn get generationId => integer().nullable()();
  IntColumn get releaseYear => integer().nullable()();
  TextColumn get introPath => text().nullable()();
  TextColumn get middlePath => text().nullable()();

  @override
  Set<Column> get primaryKey => {packSlug, id};
}

/// Finished game sessions waiting to be uploaded. Retried until the API accepts them.
class PendingSessions extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get payloadJson => text()();
  IntColumn get createdAt => integer()(); // epoch ms, UTC
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// Not sent before this time (epoch ms, UTC): the backoff after a failed attempt. 0 = send now.
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();

  /// The API refused the session for good (a 4xx), so it is never sent again. The row stays for
  /// debugging, with [lastError] saying why.
  BoolColumn get parked => boolean().withDefault(const Constant(false))();

  /// The HTTP status of the last failed attempt, or null when no response arrived (offline) or
  /// nothing failed yet. A wait the server asked for (a 5xx, a 429) is kept even when the
  /// connection comes back; a wait that was only about being offline is not.
  IntColumn get lastStatus => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The player's best provisional score for each mode and era (0 = all eras).
class LocalBests extends Table {
  TextColumn get mode => text()(); // 'intro' | 'middle'
  IntColumn get generationId => integer()();
  IntColumn get bestScore => integer()();
  IntColumn get achievedAt => integer()(); // epoch ms, UTC

  @override
  Set<Column> get primaryKey => {mode, generationId};
}

/// Counters the app keeps for itself, by name. `clip_errors` counts rounds that
/// were skipped because a clip file was missing or would not play.
class LocalCounters extends Table {
  TextColumn get name => text()();
  IntColumn get count => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {name};
}

/// The tracks of the last few sessions, so the next one can avoid them. Kept
/// apart from `pending_sessions`, which is emptied once sessions are uploaded.
class RecentSessions extends Table {
  TextColumn get sessionId => text()();
  IntColumn get playedAt => integer()(); // epoch ms, UTC
  TextColumn get trackIdsJson => text()();

  /// The score the server computed once the session was uploaded; null until then.
  /// The server decides the real score, so a results list shows this over the local one.
  IntColumn get serverScore => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sessionId};
}

/// The last `GET /v1/config` answer as JSON (one row, key `config`), so a launch with no network
/// still uses the server's tunables. Empty until the first successful fetch.
class RemoteConfigCache extends Table {
  TextColumn get key => text()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The server step of an account link that has not gone through yet (offline, or a server error),
/// so it is retried on the next start. At most one row. `kind` is `registered` or `merge`; a merge
/// keeps the guest's ID token, which the server accepts for up to 30 days.
class PendingAccountSync extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get kind => text()();
  TextColumn get anonymousIdToken => text().nullable()();
  IntColumn get createdAt => integer()(); // epoch ms, UTC

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    InstalledPacks,
    LocalTracks,
    PendingSessions,
    LocalBests,
    LocalCounters,
    RecentSessions,
    RemoteConfigCache,
    PendingAccountSync,
  ],
)
class AppDb extends _$AppDb {
  AppDb(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(localTracks, localTracks.artistId);
            await m.addColumn(localTracks, localTracks.generationId);
          }
          if (from < 3) {
            await m.createTable(localBests);
            await m.createTable(localCounters);
            await m.createTable(recentSessions);
          }
          if (from < 4) {
            await m.addColumn(pendingSessions, pendingSessions.nextAttemptAt);
            await m.addColumn(pendingSessions, pendingSessions.parked);
            await m.addColumn(pendingSessions, pendingSessions.lastStatus);
            // recent_sessions made by the `from < 3` step above already has this column.
            if (from >= 3) await m.addColumn(recentSessions, recentSessions.serverScore);
          }
          if (from < 5) await m.createTable(remoteConfigCache);
          if (from < 6) await m.createTable(pendingAccountSync);
        },
      );
}

/// Opens the on-device database file in the app's documents directory.
QueryExecutor openAppDbConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'yeman_zefen.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

final appDbProvider = Provider<AppDb>((ref) {
  final db = AppDb(openAppDbConnection());
  ref.onDispose(db.close);
  return db;
});
