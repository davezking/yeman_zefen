import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/data/clip_store.dart';
import 'package:yeman_zefen/features/packs/data/starter_pack.dart';

import 'starter_fixtures.dart';

void main() {
  late Directory base;
  late AppDb db;
  late ClipStore store;

  setUp(() {
    base = Directory.systemTemp.createTempSync('starter_pack_test');
    db = AppDb(NativeDatabase.memory());
    store = ClipStore(db: db, supportDirectory: () async => base);
  });

  tearDown(() async {
    await db.close();
    base.deleteSync(recursive: true);
  });

  StarterPack pack(MapAssetBundle bundle) =>
      StarterPack(db: db, store: store, supportDirectory: () async => base, bundle: bundle);

  test('copies every clip once, verifies it, and registers the tracks as starter clips', () async {
    final count = await pack(starterBundle(tracks: 8)).registerIfChanged();

    expect(count, 8);
    expect(await db.select(db.catalogTracks).get(), hasLength(8));
    final clips = await db.select(db.clips).get();
    expect(clips, hasLength(16));
    expect(clips.every((c) => c.source == ClipSource.starter), isTrue);
    for (final c in clips) {
      expect(c.path, ClipStore.starterPath(c.trackId, ClipKind.values.byName(c.kind)));
      expect(File(p.join(base.path, c.path)).readAsBytesSync(), starterBody(c.trackId, c.kind));
      expect(c.bytes, starterBody(c.trackId, c.kind).length);
    }
    // The catalog carries the remote urls too, so the same tracks can be fetched after an eviction.
    final track = await (db.select(db.catalogTracks)..where((t) => t.id.equals(3))).getSingle();
    expect(track.introUrl, 'https://cdn.test/clips/3-intro.mp3');
    expect(track.artistId, 104);
  });

  test('does nothing the second time, and again after an app update changes the manifest', () async {
    final bundle = starterBundle(tracks: 6);
    expect(await pack(bundle).registerIfChanged(), 6);
    expect(await pack(bundle).registerIfChanged(), 0);

    expect(await pack(starterBundle(tracks: 7, version: 2)).registerIfChanged(), 7);
    expect(await db.select(db.catalogTracks).get(), hasLength(7));
    expect(await db.select(db.clips).get(), hasLength(14));
  });

  test('repairs a clip row that went missing', () async {
    final bundle = starterBundle(tracks: 5);
    await pack(bundle).registerIfChanged();
    await store.forget(2, ClipKind.intro);

    expect(await pack(bundle).registerIfChanged(), 5);
    expect(await db.select(db.clips).get(), hasLength(10));
  });

  test('a build with no starter pack still starts', () async {
    expect(await pack(MapAssetBundle({})).registerIfChanged(), 0);
    expect(await db.select(db.clips).get(), isEmpty);
  });

  test('a clip that fails its checksum leaves its track out; the others register', () async {
    final count = await pack(starterBundle(tracks: 5, corrupt: {2})).registerIfChanged();

    expect(count, 4);
    expect((await db.select(db.catalogTracks).get()).map((t) => t.id), isNot(contains(2)));
    expect(File(p.join(base.path, ClipStore.starterPath(2, ClipKind.intro))).existsSync(), isFalse);
  });

  test('a clip from an installed pack is not downgraded to a starter clip', () async {
    await store.registerClip(
      trackId: 1,
      kind: ClipKind.intro,
      path: 'packs/golden-era/v1/1-intro.mp3',
      bytes: 9,
      source: ClipSource.pack,
    );

    await pack(starterBundle(tracks: 5)).registerIfChanged();

    final row = await (db.select(db.clips)..where((c) => c.trackId.equals(1))..where((c) => c.kind.equals('intro'))).getSingle();
    expect((row.source, row.path), (ClipSource.pack, 'packs/golden-era/v1/1-intro.mp3'));
  });

  test('a prefetched copy is replaced by the bundled one, and its file removed', () async {
    final streamFile = File(p.join(base.path, ClipStore.streamPath(1, ClipKind.intro)))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    await store.registerClip(
      trackId: 1,
      kind: ClipKind.intro,
      path: ClipStore.streamPath(1, ClipKind.intro),
      bytes: 3,
      source: ClipSource.stream,
    );

    await pack(starterBundle(tracks: 5)).registerIfChanged();

    final row = await (db.select(db.clips)..where((c) => c.trackId.equals(1))..where((c) => c.kind.equals('intro'))).getSingle();
    expect(row.source, ClipSource.starter);
    expect(streamFile.existsSync(), isFalse);
  });
}
