import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';

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

  test('upgrading from schema 6 keeps rows and adds the local values table', () async {
    final db = AppDb(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE pending_account_sync (id INTEGER NOT NULL DEFAULT 1, kind TEXT NOT NULL, '
              'anonymous_id_token TEXT, target_uid TEXT, created_at INTEGER NOT NULL, PRIMARY KEY (id))');
          raw.execute("INSERT INTO pending_account_sync (id, kind, created_at) VALUES (1, 'merge', 1)");
          raw.execute('PRAGMA user_version = 6');
        },
      ),
    );
    addTearDown(db.close);

    expect(await db.select(db.pendingAccountSync).get(), hasLength(1));
    expect(await db.select(db.localValues).get(), isEmpty);
    await db.into(db.localValues).insert(LocalValuesCompanion.insert(key: 'k', value: 'v'));
    expect((await db.select(db.localValues).getSingle()).value, 'v');
  });
}
