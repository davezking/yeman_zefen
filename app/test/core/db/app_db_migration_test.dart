import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';

void main() {
  test('upgrading from schema 1 keeps rows and adds the artist and era columns', () async {
    final db = AppDb(
      NativeDatabase.memory(
        // A database as schema 1 created it, so the upgrade path runs for real.
        setup: (raw) {
          raw.execute('CREATE TABLE installed_packs (slug TEXT NOT NULL, version INTEGER NOT NULL, '
              'manifest_json TEXT NOT NULL, installed_at INTEGER NOT NULL, total_bytes INTEGER NOT NULL, '
              'PRIMARY KEY (slug))');
          raw.execute('CREATE TABLE local_tracks (pack_slug TEXT NOT NULL, id INTEGER NOT NULL, '
              'title_am TEXT NULL, title_latin TEXT NULL, artist_am TEXT NULL, artist_latin TEXT NULL, '
              'release_year INTEGER NULL, intro_path TEXT NULL, middle_path TEXT NULL, '
              'PRIMARY KEY (pack_slug, id))');
          raw.execute('CREATE TABLE pending_sessions (id TEXT NOT NULL, payload_json TEXT NOT NULL, '
              'created_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT NULL, '
              'PRIMARY KEY (id))');
          raw.execute("INSERT INTO local_tracks (pack_slug, id, title_latin) VALUES ('old', 1, 'Old song')");
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    final old = await db.select(db.localTracks).getSingle();
    expect(old.titleLatin, 'Old song');
    expect(old.artistId, isNull);
    expect(old.generationId, isNull);

    await db.into(db.localTracks).insert(
          LocalTracksCompanion.insert(
            packSlug: 'new',
            id: 2,
            artistId: const Value(7),
            generationId: const Value(3),
          ),
        );
    final added = await (db.select(db.localTracks)..where((t) => t.packSlug.equals('new'))).getSingle();
    expect(added.artistId, 7);
    expect(added.generationId, 3);
  });
}
