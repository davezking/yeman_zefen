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

  @override
  Set<Column> get primaryKey => {sessionId};
}

@DriftDatabase(
  tables: [InstalledPacks, LocalTracks, PendingSessions, LocalBests, LocalCounters, RecentSessions],
)
class AppDb extends _$AppDb {
  AppDb(super.executor);

  @override
  int get schemaVersion => 3;

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
