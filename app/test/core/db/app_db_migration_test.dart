import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';

/// The pack tables as schema 1 made them. Every real database has them; the upgrade to schema 8
/// reads them to fill the catalog.
const _packTableSql = [
  'CREATE TABLE installed_packs (slug TEXT NOT NULL, version INTEGER NOT NULL, '
      'manifest_json TEXT NOT NULL, installed_at INTEGER NOT NULL, total_bytes INTEGER NOT NULL, '
      'PRIMARY KEY (slug))',
  'CREATE TABLE local_tracks (pack_slug TEXT NOT NULL, id INTEGER NOT NULL, '
      'title_am TEXT NULL, title_latin TEXT NULL, artist_am TEXT NULL, artist_latin TEXT NULL, '
      'artist_id INTEGER NULL, generation_id INTEGER NULL, '
      'release_year INTEGER NULL, intro_path TEXT NULL, middle_path TEXT NULL, '
      'PRIMARY KEY (pack_slug, id))',
];

void main() {
  test('upgrading from schema 1 keeps rows, adds the artist and era columns and the new tables', () async {
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

    expect(await db.select(db.localBests).get(), isEmpty);
    expect(await db.select(db.localCounters).get(), isEmpty);
    expect(await db.select(db.recentSessions).get(), isEmpty);
  });

  test('upgrading from schema 2 keeps rows and adds the tables for scores, counters and history', () async {
    final db = AppDb(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE installed_packs (slug TEXT NOT NULL, version INTEGER NOT NULL, '
              'manifest_json TEXT NOT NULL, installed_at INTEGER NOT NULL, total_bytes INTEGER NOT NULL, '
              'PRIMARY KEY (slug))');
          raw.execute('CREATE TABLE local_tracks (pack_slug TEXT NOT NULL, id INTEGER NOT NULL, '
              'title_am TEXT NULL, title_latin TEXT NULL, artist_am TEXT NULL, artist_latin TEXT NULL, '
              'artist_id INTEGER NULL, generation_id INTEGER NULL, '
              'release_year INTEGER NULL, intro_path TEXT NULL, middle_path TEXT NULL, '
              'PRIMARY KEY (pack_slug, id))');
          raw.execute('CREATE TABLE pending_sessions (id TEXT NOT NULL, payload_json TEXT NOT NULL, '
              'created_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT NULL, '
              'PRIMARY KEY (id))');
          raw.execute("INSERT INTO pending_sessions (id, payload_json, created_at) VALUES ('s1', '{}', 5)");
          raw.execute("INSERT INTO local_tracks (pack_slug, id, artist_id, generation_id) VALUES ('p', 1, 7, 2)");
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(db.close);

    expect((await db.select(db.pendingSessions).getSingle()).id, 's1');
    expect((await db.select(db.localTracks).getSingle()).artistId, 7);

    await db.into(db.localBests).insert(
          LocalBestsCompanion.insert(mode: 'intro', generationId: 0, bestScore: 900, achievedAt: 1),
        );
    await db.into(db.localCounters).insert(LocalCountersCompanion.insert(name: 'clip_errors'));
    await db.into(db.recentSessions).insert(
          RecentSessionsCompanion.insert(sessionId: 's1', playedAt: 1, trackIdsJson: '[1]'),
        );
    expect((await db.select(db.localBests).getSingle()).bestScore, 900);
    expect((await db.select(db.localCounters).getSingle()).count, 0);
    expect((await db.select(db.recentSessions).getSingle()).trackIdsJson, '[1]');
  });

  test('upgrading from schema 3 keeps queued sessions and adds the sync columns', () async {
    final db = AppDb(
      NativeDatabase.memory(
        setup: (raw) {
          _packTableSql.forEach(raw.execute);
          raw.execute('CREATE TABLE pending_sessions (id TEXT NOT NULL, payload_json TEXT NOT NULL, '
              'created_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT NULL, '
              'PRIMARY KEY (id))');
          raw.execute('CREATE TABLE recent_sessions (session_id TEXT NOT NULL, played_at INTEGER NOT NULL, '
              'track_ids_json TEXT NOT NULL, PRIMARY KEY (session_id))');
          raw.execute("INSERT INTO pending_sessions (id, payload_json, created_at, attempts) VALUES ('s1', '{}', 5, 2)");
          raw.execute("INSERT INTO recent_sessions (session_id, played_at, track_ids_json) VALUES ('s1', 5, '[1]')");
          raw.execute('PRAGMA user_version = 3');
        },
      ),
    );
    addTearDown(db.close);

    final queued = await db.select(db.pendingSessions).getSingle();
    expect(queued.id, 's1');
    expect(queued.attempts, 2);
    expect(queued.nextAttemptAt, 0, reason: 'a queued session is due straight away');
    expect(queued.parked, isFalse);
    expect(queued.lastStatus, isNull);
    expect((await db.select(db.recentSessions).getSingle()).serverScore, isNull);
  });

  test('upgrading from schema 4 keeps rows and adds the remote config cache', () async {
    final db = AppDb(
      NativeDatabase.memory(
        setup: (raw) {
          _packTableSql.forEach(raw.execute);
          raw.execute('CREATE TABLE local_counters (name TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0, '
              'PRIMARY KEY (name))');
          raw.execute("INSERT INTO local_counters (name, count) VALUES ('clip_errors', 3)");
          raw.execute('PRAGMA user_version = 4');
        },
      ),
    );
    addTearDown(db.close);

    expect((await db.select(db.localCounters).getSingle()).count, 3);
    expect(await db.select(db.remoteConfigCache).get(), isEmpty);
    await db.into(db.remoteConfigCache).insert(RemoteConfigCacheCompanion.insert(key: 'config', json: '{}'));
    expect(await db.select(db.remoteConfigCache).get(), hasLength(1));
  });

  test('upgrading from schema 5 keeps rows and adds the pending account sync table', () async {
    final db = AppDb(
      NativeDatabase.memory(
        setup: (raw) {
          _packTableSql.forEach(raw.execute);
          raw.execute('CREATE TABLE remote_config_cache (key TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (key))');
          raw.execute("INSERT INTO remote_config_cache (key, json) VALUES ('config', '{}')");
          raw.execute('PRAGMA user_version = 5');
        },
      ),
    );
    addTearDown(db.close);

    expect(await db.select(db.remoteConfigCache).get(), hasLength(1));
    expect(await db.select(db.pendingAccountSync).get(), isEmpty);
    await db.into(db.pendingAccountSync).insert(PendingAccountSyncCompanion.insert(kind: 'merge', createdAt: 1));
    expect((await db.select(db.pendingAccountSync).getSingle()).id, 1);
  });

  test('upgrading from schema 6 keeps rows and adds the settings table', () async {
    final db = AppDb(
      NativeDatabase.memory(
        setup: (raw) {
          _packTableSql.forEach(raw.execute);
          raw.execute('CREATE TABLE pending_account_sync (id INTEGER NOT NULL DEFAULT 1, kind TEXT NOT NULL, '
              'anonymous_id_token TEXT NULL, target_uid TEXT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (id))');
          raw.execute("INSERT INTO pending_account_sync (kind, created_at) VALUES ('merge', 9)");
          raw.execute('PRAGMA user_version = 6');
        },
      ),
    );
    addTearDown(db.close);

    expect((await db.select(db.pendingAccountSync).getSingle()).kind, 'merge');
    expect(await db.select(db.appSettings).get(), isEmpty);
    await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: 'locale', value: 'am'));
    expect((await db.select(db.appSettings).getSingle()).value, 'am');
  });

  group('upgrading from schema 7', () {
    String manifest(int id) => jsonEncode({
          'schema': 1,
          'slug': 'golden-era',
          'version': 2,
          'publishedAt': 1,
          'names': {'am': 'a', 'en': 'e'},
          'tracks': [
            {
              'id': id,
              'artistId': 7,
              'clips': {
                'intro': {'url': 'https://cdn.test/$id-intro.mp3', 'sha256': 'a' * 64, 'bytes': 111, 'lengthMs': 10000},
                'middle': {'url': 'https://cdn.test/$id-middle.mp3', 'sha256': 'b' * 64, 'bytes': 222, 'lengthMs': 10000},
              },
            },
          ],
          'totalBytes': 333,
        });

    AppDb oldDb(void Function(void Function(String sql) run) seed) {
      return AppDb(
        NativeDatabase.memory(
          setup: (raw) {
            _packTableSql.forEach(raw.execute);
            raw.execute('CREATE TABLE app_settings (key TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY (key))');
            seed(raw.execute);
            raw.execute('PRAGMA user_version = 7');
          },
        ),
      );
    }

    test('installed packs keep playing: their tracks move into the catalog and their clips into the clip store', () async {
      final db = oldDb((run) {
        run("INSERT INTO installed_packs VALUES ('golden-era', 2, '${manifest(41).replaceAll("'", "''")}', 5, 333)");
        run("INSERT INTO local_tracks VALUES ('golden-era', 41, 'ዘፈን', 'Song', 'ድምፃዊ', 'Artist', 7, 2, 1975, "
            "'packs/golden-era/v2/41-intro.mp3', 'packs/golden-era/v2/41-middle.mp3')");
      });
      addTearDown(db.close);

      final track = await db.select(db.catalogTracks).getSingle();
      expect((track.id, track.artistId, track.generationId, track.releaseYear), (41, 7, 2, 1975));
      expect((track.titleLatin, track.artistLatin), ('Song', 'Artist'));
      expect((track.introUrl, track.introSha256, track.introBytes), ('https://cdn.test/41-intro.mp3', 'a' * 64, 111));
      expect((track.middleUrl, track.middleSha256, track.middleBytes), ('https://cdn.test/41-middle.mp3', 'b' * 64, 222));

      final clips = await (db.select(db.clips)..orderBy([(c) => OrderingTerm.asc(c.kind)])).get();
      expect(clips.map((c) => (c.trackId, c.kind, c.path, c.bytes, c.source)), [
        (41, 'intro', 'packs/golden-era/v2/41-intro.mp3', 111, ClipSource.pack),
        (41, 'middle', 'packs/golden-era/v2/41-middle.mp3', 222, ClipSource.pack),
      ]);
      // The pack itself is untouched.
      expect((await db.select(db.installedPacks).getSingle()).version, 2);
      expect(await db.select(db.localTracks).get(), hasLength(1));
    });

    test('a pack whose manifest cannot be read still migrates, with no urls', () async {
      final db = oldDb((run) {
        run("INSERT INTO installed_packs VALUES ('golden-era', 2, 'not json', 5, 333)");
        run("INSERT INTO local_tracks VALUES ('golden-era', 41, NULL, 'Song', NULL, 'Artist', 7, 2, NULL, "
            "'packs/golden-era/v2/41-intro.mp3', NULL)");
      });
      addTearDown(db.close);

      final track = await db.select(db.catalogTracks).getSingle();
      expect(track.id, 41);
      expect(track.introUrl, isNull);
      final clip = await db.select(db.clips).getSingle();
      expect((clip.kind, clip.bytes, clip.source), ('intro', 0, ClipSource.pack));
    });

    test('a track in two packs is migrated once; rows without an artist are left out', () async {
      final db = oldDb((run) {
        run("INSERT INTO local_tracks VALUES ('a', 41, NULL, 'Song', NULL, 'Artist', 7, 2, NULL, 'packs/a/v1/41-intro.mp3', 'packs/a/v1/41-middle.mp3')");
        run("INSERT INTO local_tracks VALUES ('b', 41, NULL, 'Song', NULL, 'Artist', 7, 2, NULL, 'packs/b/v1/41-intro.mp3', 'packs/b/v1/41-middle.mp3')");
        run("INSERT INTO local_tracks VALUES ('a', 42, NULL, 'Old', NULL, NULL, NULL, NULL, NULL, 'packs/a/v1/42-intro.mp3', NULL)");
      });
      addTearDown(db.close);

      expect((await db.select(db.catalogTracks).get()).map((t) => t.id), [41]);
      expect(await db.select(db.clips).get(), hasLength(2));
    });
  });

  test('upgrading from schema 8 keeps clips, unbroken, and adds the clip report queue', () async {
    final db = AppDb(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE clips (track_id INTEGER NOT NULL, kind TEXT NOT NULL, path TEXT NOT NULL, '
              'bytes INTEGER NOT NULL, source TEXT NOT NULL, last_played_at INTEGER NOT NULL, '
              'PRIMARY KEY (track_id, kind))');
          raw.execute("INSERT INTO clips VALUES (4, 'intro', 'packs/p/v1/4-intro.mp3', 10, 'pack', 1)");
          raw.execute('PRAGMA user_version = 8');
        },
      ),
    );
    addTearDown(db.close);

    final clip = await db.select(db.clips).getSingle();
    expect((clip.trackId, clip.path, clip.broken), (4, 'packs/p/v1/4-intro.mp3', false));
    await db.into(db.pendingClipReports).insert(
          PendingClipReportsCompanion.insert(trackId: 4, kind: 'intro', error: 'decode_error', createdAt: 1),
        );
    expect((await db.select(db.pendingClipReports).getSingle()).error, 'decode_error');
  });
}
