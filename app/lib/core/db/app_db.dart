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

@DriftDatabase(tables: [InstalledPacks, LocalTracks, PendingSessions])
class AppDb extends _$AppDb {
  AppDb(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
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
