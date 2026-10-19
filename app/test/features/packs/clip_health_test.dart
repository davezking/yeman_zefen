import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/game/data/game_library.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/packs/data/clip_checker.dart';
import 'package:yeman_zefen/features/packs/data/clip_store.dart';
import 'package:yeman_zefen/features/packs/data/pack_installer.dart';
import 'package:yeman_zefen/features/packs/data/starter_pack.dart';

import 'pack_fixtures.dart';
import 'starter_fixtures.dart';

const day = 86400000;

void main() {
  late Directory base;
  late AppDb db;
  late ClipStore store;
  late FakeClipDownloader downloader;
  late PackInstaller installer;
  var now = 1000;

  setUp(() {
    now = 1000;
    base = Directory.systemTemp.createTempSync('clip_health_test');
    db = AppDb(NativeDatabase.memory());
    store = ClipStore(db: db, supportDirectory: () async => base, nowMs: () => now);
    downloader = FakeClipDownloader(base);
    installer = PackInstaller(db: db, downloader: downloader, supportDirectory: () async => base, store: store);
  });

  tearDown(() async {
    await installer.dispose();
    await db.close();
    base.deleteSync(recursive: true);
  });

  Future<void> install({int version = 1, int tracks = 3}) {
    final json = manifestJson(version: version, tracks: tracks);
    return installer.install(manifestOf(json), json, expectedSlug: 'golden-era', expectedVersion: version);
  }

  File file(String relative) => File(p.join(base.path, relative));
  String packPath(int id, String kind, {int version = 1}) => 'packs/golden-era/v$version/$id-$kind.mp3';

  /// Flips one byte of a file, like damage on disk.
  void corrupt(String relative) {
    final bytes = file(relative).readAsBytesSync();
    bytes[0] ^= 0xff;
    file(relative).writeAsBytesSync(bytes);
  }

  Future<Clip?> row(int id, String kind) =>
      (db.select(db.clips)..where((c) => c.trackId.equals(id) & c.kind.equals(kind))).getSingleOrNull();

  Future<bool> playable(int id, {GameMode mode = GameMode.intro}) async =>
      (await loadGameLibrary(db, base)).hasClip(id, mode);

  group('marking a clip broken', () {
    test('a cached clip is simply dropped, file and row', () async {
      file(ClipStore.streamPath(5, ClipKind.intro)).createSync(recursive: true);
      await store.registerClip(trackId: 5, kind: ClipKind.intro, path: ClipStore.streamPath(5, ClipKind.intro), bytes: 1, source: ClipSource.stream);

      await store.markBroken(5, ClipKind.intro);

      expect(await row(5, 'intro'), isNull);
      expect(file(ClipStore.streamPath(5, ClipKind.intro)).existsSync(), isFalse);
    });

    test('a pack clip stays, marked broken, and no game counts it as on the phone', () async {
      await install();
      await store.markBroken(2, ClipKind.intro);

      expect((await row(2, 'intro'))!.broken, isTrue);
      expect((await row(2, 'middle'))!.broken, isFalse);
      expect(await playable(2), isFalse);
      expect(await playable(2, mode: GameMode.middle), isTrue);
      // It can still be fetched while playing online.
      expect((await loadGameLibrary(db, base)).playableIds(GameMode.intro, includeFetchable: true), contains(2));
    });

    test('a copy that verifies replaces a broken clip, even one that would otherwise stay', () async {
      await install();
      await store.markBroken(2, ClipKind.intro);
      file(ClipStore.streamPath(2, ClipKind.intro)).createSync(recursive: true);

      final kept = await store.registerClip(
        trackId: 2,
        kind: ClipKind.intro,
        path: ClipStore.streamPath(2, ClipKind.intro),
        bytes: 1,
        source: ClipSource.stream,
        replace: false,
      );

      expect((kept.source, kept.broken), (ClipSource.stream, false));
      expect(await playable(2), isTrue);
    });
  });

  group('checking an installed pack', () {
    test('a file with one byte changed is downloaded again and verified', () async {
      await install();
      corrupt(packPath(2, 'intro'));
      downloader.calls.clear();

      expect(await installer.check('golden-era', allowDownloads: true), isTrue);

      expect(downloader.calls, [clipUrl(2, 'intro', 1)]);
      expect(sha256Hex(file(packPath(2, 'intro')).readAsBytesSync()), sha256Hex(bodyFor(clipUrl(2, 'intro', 1))));
      expect(file('${packPath(2, 'intro')}.part').existsSync(), isFalse);
      expect((await row(2, 'intro'))!.broken, isFalse);
    });

    test('offline, a bad file is marked broken and the check says it is not done', () async {
      await install();
      corrupt(packPath(2, 'intro'));
      file(packPath(3, 'middle')).deleteSync();

      expect(await installer.check('golden-era', allowDownloads: false), isFalse);

      expect((await row(2, 'intro'))!.broken, isTrue);
      expect((await row(3, 'middle'))!.broken, isTrue);
      expect((await row(1, 'intro'))!.broken, isFalse);
      expect(await playable(2), isFalse);

      // Back online: both are repaired.
      expect(await installer.check('golden-era', allowDownloads: true), isTrue);
      expect((await row(2, 'intro'))!.broken, isFalse);
      expect((await row(3, 'middle'))!.broken, isFalse);
      expect(await playable(2), isTrue);
    });

    test('a clip that would not play is downloaded again even though its file matches', () async {
      await install();
      await store.markBroken(1, ClipKind.middle);
      downloader.calls.clear();

      expect(await installer.check('golden-era', allowDownloads: true), isTrue);

      expect(downloader.calls, [clipUrl(1, 'middle', 1)]);
      expect((await row(1, 'middle'))!.broken, isFalse);
    });

    test('a download that keeps failing its checksum leaves the clip broken', () async {
      await install();
      corrupt(packPath(2, 'intro'));
      downloader.corruptTimes[clipUrl(2, 'intro', 1)] = 99;

      expect(await installer.check('golden-era', allowDownloads: true), isFalse);
      expect((await row(2, 'intro'))!.broken, isTrue);
      expect(file('${packPath(2, 'intro')}.part').existsSync(), isFalse);
    });

    test('a good file whose row went missing, or that a cached copy replaced, is the pack\'s again', () async {
      await install();
      await store.forget(1, ClipKind.intro);
      // A broken pack clip that a game then fetched into the cache.
      await store.markBroken(2, ClipKind.intro);
      final stream = ClipStore.streamPath(2, ClipKind.intro);
      file(stream)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bodyFor(clipUrl(2, 'intro', 1)));
      await store.registerClip(trackId: 2, kind: ClipKind.intro, path: stream, bytes: 1, source: ClipSource.stream, replace: false);
      downloader.calls.clear();

      expect(await installer.check('golden-era', allowDownloads: true), isTrue);

      expect(((await row(1, 'intro'))!.source, (await row(1, 'intro'))!.path), (ClipSource.pack, packPath(1, 'intro')));
      expect(((await row(2, 'intro'))!.source, (await row(2, 'intro'))!.path), (ClipSource.pack, packPath(2, 'intro')));
      expect(file(stream).existsSync(), isFalse, reason: 'the cached copy is not kept twice');
      expect(downloader.calls, isEmpty, reason: 'both pack files were fine');
    });

    test('a built-in clip the pack also has is left alone', () async {
      await StarterPack(db: db, store: store, supportDirectory: () async => base, bundle: starterBundle(tracks: 3))
          .registerIfChanged();
      await install();
      downloader.calls.clear();

      expect(await installer.check('golden-era', allowDownloads: true), isTrue);
      expect(downloader.calls, isEmpty);
      expect((await row(1, 'intro'))!.source, ClipSource.starter);
    });

    test('installing a pack replaces a broken built-in clip with the pack\'s own file', () async {
      await StarterPack(db: db, store: store, supportDirectory: () async => base, bundle: starterBundle(tracks: 3))
          .registerIfChanged();
      await store.markBroken(1, ClipKind.intro);

      await install();

      final intro = (await row(1, 'intro'))!;
      expect((intro.source, intro.path, intro.broken), (ClipSource.pack, packPath(1, 'intro'), false));
      expect(file(packPath(1, 'intro')).existsSync(), isTrue);
      expect((await row(1, 'middle'))!.source, ClipSource.starter, reason: 'the good built-in clip stays');
    });

    test('a pack that is not installed has nothing to check', () async {
      expect(await installer.check('nope', allowDownloads: true), isTrue);
    });
  });

  group('checking cached clips', () {
    test('drops a cached clip that no longer matches the catalog, and keeps the good ones', () async {
      await install(tracks: 2);
      for (final id in [1, 2]) {
        final path = ClipStore.streamPath(id, ClipKind.middle);
        // Replace the pack rows with cached copies of the same clips.
        file(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(bodyFor(clipUrl(id, 'middle', 1)));
        await store.forget(id, ClipKind.middle);
        await store.registerClip(trackId: id, kind: ClipKind.middle, path: path, bytes: 1, source: ClipSource.stream);
      }
      corrupt(ClipStore.streamPath(2, ClipKind.middle));

      expect(await store.checkStreamClips(), 1);

      expect((await row(1, 'middle'))!.source, ClipSource.stream);
      expect(await row(2, 'middle'), isNull);
      expect(file(ClipStore.streamPath(2, ClipKind.middle)).existsSync(), isFalse);
    });
  });

  group('checking starter clips', () {
    test('a damaged starter clip is excluded until the next app update', () async {
      final starter = StarterPack(db: db, store: store, supportDirectory: () async => base, bundle: starterBundle(tracks: 3));
      await starter.registerIfChanged();
      corrupt(ClipStore.starterPath(2, ClipKind.intro));

      expect(await starter.checkClips(), 1);
      expect((await row(2, 'intro'))!.broken, isTrue);

      // The same build starting again does not bring it back.
      await starter.registerIfChanged();
      expect((await row(2, 'intro'))!.broken, isTrue);

      // An update with a new starter pack copies it again.
      final updated = StarterPack(db: db, store: store, supportDirectory: () async => base, bundle: starterBundle(tracks: 3, version: 2));
      await updated.registerIfChanged();
      expect((await row(2, 'intro'))!.broken, isFalse);
      expect(file(ClipStore.starterPath(2, ClipKind.intro)).readAsBytesSync(), starterBody(2, 'intro'));
    });
  });

  group('the checker on start', () {
    late StarterPack starter;
    var online = true;

    ClipChecker checker() => ClipChecker(
          db: db,
          store: store,
          installer: installer,
          starter: starter,
          allowDownloads: () async => online,
          nowMs: () => now,
        );

    setUp(() {
      online = true;
      starter = StarterPack(db: db, store: store, supportDirectory: () async => base, bundle: starterBundle(tracks: 0));
    });

    Future<Map<String, String>> marks() async => {for (final r in await db.select(db.appSettings).get()) r.key: r.value};

    test('a corrupted pack clip is repaired on the next launch', () async {
      await install();
      corrupt(packPath(2, 'middle'));

      await checker().run();

      expect(sha256Hex(file(packPath(2, 'middle')).readAsBytesSync()), sha256Hex(bodyFor(clipUrl(2, 'middle', 1))));
      expect((await marks())[ClipChecker.packKey('golden-era')], '1:1000');
    });

    test('checks each pack version once, then weekly', () async {
      await install();
      await checker().run();
      corrupt(packPath(1, 'intro'));

      now += 6 * day;
      await checker().run();
      expect(sha256Hex(file(packPath(1, 'intro')).readAsBytesSync()), isNot(sha256Hex(bodyFor(clipUrl(1, 'intro', 1)))),
          reason: 'not due yet');

      now += day;
      await checker().run();
      expect(sha256Hex(file(packPath(1, 'intro')).readAsBytesSync()), sha256Hex(bodyFor(clipUrl(1, 'intro', 1))));
    });

    test('a new pack version is checked at once', () async {
      await install();
      await checker().run();
      await install(version: 2);
      corrupt(packPath(1, 'intro', version: 2));

      now += day;
      await checker().run();
      expect((await marks())[ClipChecker.packKey('golden-era')], '2:${1000 + day}');
      expect(sha256Hex(file(packPath(1, 'intro', version: 2)).readAsBytesSync()), sha256Hex(bodyFor(clipUrl(1, 'intro', 2))));
    });

    test('offline the bad clip stays broken and the check stays due until it is repaired', () async {
      await install();
      corrupt(packPath(3, 'intro'));
      online = false;
      await checker().run();
      expect((await row(3, 'intro'))!.broken, isTrue);
      expect((await marks())[ClipChecker.packKey('golden-era')], isNull);

      // The next launch, a minute later and online.
      online = true;
      now += 60000;
      await checker().run();
      expect((await row(3, 'intro'))!.broken, isFalse);
      expect((await marks())[ClipChecker.packKey('golden-era')], '1:${1000 + 60000}');
    });

    test('a clip that broke while playing makes its pack due on the next launch', () async {
      await install();
      await checker().run();
      await store.markBroken(2, ClipKind.intro);
      downloader.calls.clear();

      now += 60000;
      await checker().run();
      expect(downloader.calls, [clipUrl(2, 'intro', 1)]);
      expect((await row(2, 'intro'))!.broken, isFalse);
    });

    test('cached and starter clips are checked weekly', () async {
      await checker().run();
      final first = await marks();
      expect(first[ClipChecker.streamKey], '1000');
      expect(first[ClipChecker.starterKey], '1000');

      now += day;
      await checker().run();
      expect((await marks())[ClipChecker.streamKey], '1000');

      now += 6 * day;
      await checker().run();
      expect((await marks())[ClipChecker.streamKey], '${1000 + 7 * day}');
    });
  });
}
