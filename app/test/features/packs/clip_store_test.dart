import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/data/clip_settings.dart';
import 'package:yeman_zefen/features/packs/data/clip_store.dart';

void main() {
  late Directory base;
  late AppDb db;
  late ClipStore store;
  var now = 1000;

  setUp(() {
    now = 1000;
    base = Directory.systemTemp.createTempSync('clip_store_test');
    db = AppDb(NativeDatabase.memory());
    store = ClipStore(db: db, supportDirectory: () async => base, nowMs: () => now);
  });

  tearDown(() async {
    await db.close();
    base.deleteSync(recursive: true);
  });

  /// Registers a clip and writes its file.
  Future<void> add(int id, String source, int bytes, {ClipKind kind = ClipKind.intro, int at = 0}) async {
    final path = source == ClipSource.stream
        ? ClipStore.streamPath(id, kind)
        : source == ClipSource.starter
            ? ClipStore.starterPath(id, kind)
            : 'packs/p/v1/$id-${kind.name}.mp3';
    File(p.join(base.path, path))
      ..createSync(recursive: true)
      ..writeAsBytesSync([0]);
    now = at;
    await store.registerClip(trackId: id, kind: kind, path: path, bytes: bytes, source: source);
  }

  bool onDisk(int id, String source, {ClipKind kind = ClipKind.intro}) {
    final path = source == ClipSource.stream
        ? ClipStore.streamPath(id, kind)
        : source == ClipSource.starter
            ? ClipStore.starterPath(id, kind)
            : 'packs/p/v1/$id-${kind.name}.mp3';
    return File(p.join(base.path, path)).existsSync();
  }

  Future<Set<int>> ids(String source) async =>
      {for (final c in await (db.select(db.clips)..where((t) => t.source.equals(source))).get()) c.trackId};

  group('eviction', () {
    test('removes the least recently played stream clips first, until they fit', () async {
      await add(1, ClipSource.stream, 100, at: 10);
      await add(2, ClipSource.stream, 100, at: 30);
      await add(3, ClipSource.stream, 100, at: 20);

      final freed = await store.evict(200);

      expect(freed, 100);
      expect(await ids(ClipSource.stream), {2, 3});
      expect(onDisk(1, ClipSource.stream), isFalse);
      expect(onDisk(2, ClipSource.stream), isTrue);
    });

    test('a clip that was just played goes to the back of the line', () async {
      await add(1, ClipSource.stream, 100, at: 10);
      await add(2, ClipSource.stream, 100, at: 20);
      now = 50;
      await store.touch(1, ClipKind.intro);

      await store.evict(100);

      expect(await ids(ClipSource.stream), {1});
    });

    test('never removes starter or pack clips, however large they are', () async {
      await add(1, ClipSource.starter, 500, at: 1);
      await add(2, ClipSource.pack, 500, at: 2);
      await add(3, ClipSource.stream, 100, at: 3);

      await store.evict(0);

      expect(await ids(ClipSource.stream), isEmpty);
      expect(await ids(ClipSource.starter), {1});
      expect(await ids(ClipSource.pack), {2});
      expect(onDisk(1, ClipSource.starter), isTrue);
      expect(onDisk(2, ClipSource.pack), isTrue);
    });

    test('does nothing while the cache fits', () async {
      await add(1, ClipSource.stream, 100);
      expect(await store.evict(100), 0);
      expect(await ids(ClipSource.stream), {1});
    });

    test('the cap is 50 MB by default and a setting', () async {
      expect(ClipStore.defaultStreamCacheCapBytes, 50 * 1024 * 1024);
      final settings = ClipSettings(db);
      expect(await settings.streamCacheCapBytes(), 50 * 1024 * 1024);
      await settings.setStreamCacheCapMb(20);
      expect(await settings.streamCacheCapBytes(), 20 * 1024 * 1024);
    });
  });

  test('clearing the cache removes stream clips only', () async {
    await add(1, ClipSource.stream, 100);
    await add(2, ClipSource.starter, 100);
    await add(3, ClipSource.pack, 100);

    await store.clearStreamCache();

    expect(await ids(ClipSource.stream), isEmpty);
    expect(onDisk(1, ClipSource.stream), isFalse);
    expect(await ids(ClipSource.starter), {2});
    expect(await ids(ClipSource.pack), {3});
  });

  test('storage usage adds up each source', () async {
    await add(1, ClipSource.starter, 10);
    await add(2, ClipSource.starter, 20, kind: ClipKind.middle);
    await add(3, ClipSource.stream, 5);
    await add(4, ClipSource.pack, 100);

    const expected = StorageUsage(starterBytes: 30, streamBytes: 5, packBytes: 100);
    expect(await store.usage(), expected);
    expect(expected.totalBytes, 135);
    expect(await store.watchUsage().first, expected);
  });

  test('the data saver is on for mobile data unless the player turned it off', () async {
    final settings = ClipSettings(db);
    expect(await settings.prefetchOnMobile(), isTrue);
    await settings.setPrefetchOnMobile(false);
    expect(await settings.prefetchOnMobile(), isFalse);
    await settings.setPrefetchOnMobile(true);
    expect(await settings.prefetchOnMobile(), isTrue);
  });
}
