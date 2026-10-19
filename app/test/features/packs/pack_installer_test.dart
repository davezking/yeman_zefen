import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/data/clip_store.dart';
import 'package:yeman_zefen/features/packs/data/pack_installer.dart';
import 'package:yeman_zefen/features/packs/data/pack_manifest.dart';
import 'package:yeman_zefen/features/packs/domain/pack_install_progress.dart';

import 'pack_fixtures.dart';

void main() {
  late Directory base;
  late AppDb db;
  late FakeClipDownloader downloader;
  late PackInstaller installer;

  setUp(() {
    base = Directory.systemTemp.createTempSync('pack_installer_test');
    db = AppDb(NativeDatabase.memory());
    downloader = FakeClipDownloader(base);
    installer = PackInstaller(
      db: db,
      downloader: downloader,
      supportDirectory: () async => base,
    );
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

  bool fileExists(String relative) => File(p.join(base.path, relative)).existsSync();

  Future<bool> fileHasBytes(String relative, List<int> bytes) async =>
      sha256Hex(await File(p.join(base.path, relative)).readAsBytes()) == sha256Hex(bytes);

  test('downloads, verifies and registers every track', () async {
    await install();

    final pack = await db.select(db.installedPacks).getSingle();
    expect(pack.slug, 'golden-era');
    expect(pack.version, 1);
    expect(pack.manifestJson, manifestJson());

    final tracks = await db.select(db.localTracks).get();
    expect(tracks, hasLength(3));
    for (final t in tracks) {
      expect(t.artistId, 7);
      expect(t.generationId, 2);
      expect(t.introPath, 'packs/golden-era/v1/${t.id}-intro.mp3');
      expect(t.middlePath, 'packs/golden-era/v1/${t.id}-middle.mp3');
      expect(fileExists(t.introPath!), isTrue);
      expect(fileExists(t.middlePath!), isTrue);
    }
    expect(await installer.installedVersion('golden-era'), 1);
  });

  test('adds the tracks to the catalog and every clip to the clip store as a pack clip', () async {
    await install();

    final catalog = await db.select(db.catalogTracks).get();
    expect(catalog.map((t) => t.id), unorderedEquals([1, 2, 3]));
    final track = catalog.firstWhere((t) => t.id == 2);
    expect(track.introUrl, clipUrl(2, 'intro', 1));
    expect(track.introSha256, sha256Hex(bodyFor(clipUrl(2, 'intro', 1))));
    expect(track.middleBytes, bodyFor(clipUrl(2, 'middle', 1)).length);

    final clips = await db.select(db.clips).get();
    expect(clips, hasLength(6));
    expect(clips.every((c) => c.source == ClipSource.pack), isTrue);
    final intro = clips.firstWhere((c) => c.trackId == 2 && c.kind == 'intro');
    expect(intro.path, 'packs/golden-era/v1/2-intro.mp3');
    expect(intro.bytes, bodyFor(clipUrl(2, 'intro', 1)).length);
  });

  test('a prefetched copy of a clip is replaced by the pack\'s, and its file removed', () async {
    final streamPath = ClipStore.streamPath(2, ClipKind.intro);
    File(p.join(base.path, streamPath))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    await db.into(db.clips).insert(
          ClipsCompanion.insert(
            trackId: 2,
            kind: 'intro',
            path: streamPath,
            bytes: 1,
            source: ClipSource.stream,
            lastPlayedAt: 1,
          ),
        );

    await install();

    final row = await (db.select(db.clips)..where((c) => c.trackId.equals(2))..where((c) => c.kind.equals('intro'))).getSingle();
    expect((row.source, row.path), (ClipSource.pack, 'packs/golden-era/v1/2-intro.mp3'));
    expect(fileExists(streamPath), isFalse);
  });

  test('an upgrade moves the clip rows to the new version, and drops tracks it no longer has', () async {
    await install(version: 1);
    await install(version: 2, tracks: 2);

    final clips = await db.select(db.clips).get();
    expect(clips, hasLength(4));
    expect(clips.every((c) => c.path.contains('/v2/')), isTrue);
    expect(clips.map((c) => c.trackId).toSet(), {1, 2});
  });

  test('a track the new version drops keeps its clip from another installed pack', () async {
    // Both packs have tracks 1-3; golden-era is installed last, so the clip rows point at it.
    final other = manifestJson(slug: 'other-pack', tracks: 3);
    await installer.install(manifestOf(other), other, expectedSlug: 'other-pack', expectedVersion: 1);
    await install(version: 1, tracks: 3);
    expect((await db.select(db.clips).get()).every((c) => c.path.startsWith('packs/golden-era/')), isTrue);

    await install(version: 2, tracks: 2); // drops track 3

    final three = await (db.select(db.clips)..where((c) => c.trackId.equals(3))).get();
    expect(three.map((c) => (c.kind, c.path, c.source)), unorderedEquals([
      ('intro', 'packs/other-pack/v1/3-intro.mp3', ClipSource.pack),
      ('middle', 'packs/other-pack/v1/3-middle.mp3', ClipSource.pack),
    ]));
    expect(fileExists('packs/other-pack/v1/3-intro.mp3'), isTrue);
  });

  test('a failed install adds nothing to the catalog or the clip store', () async {
    downloader.failing.add(clipUrl(2, 'middle', 1));
    await expectLater(install(), throwsA(isA<PackInstallException>()));

    expect(await db.select(db.catalogTracks).get(), isEmpty);
    expect(await db.select(db.clips).get(), isEmpty);
  });

  test('never runs more than 4 downloads at once', () async {
    await install(tracks: 6); // 12 clips
    expect(downloader.calls, hasLength(12));
    expect(downloader.maxRunning, lessThanOrEqualTo(4));
    expect(downloader.maxRunning, greaterThan(1));
  });

  test('a checksum mismatch is re-fetched and then succeeds', () async {
    final url = clipUrl(2, 'intro', 1);
    downloader.corruptTimes[url] = 1;

    await install();

    expect(downloader.calls.where((u) => u == url), hasLength(2));
    expect(await db.select(db.installedPacks).get(), hasLength(1));
    expect(fileExists('packs/golden-era/v1/2-intro.mp3'), isTrue);
  });

  test('two mismatches in a row still succeed on the third download', () async {
    final url = clipUrl(1, 'middle', 1);
    downloader.corruptTimes[url] = 2;

    await install();

    expect(downloader.calls.where((u) => u == url), hasLength(3));
    expect(await db.select(db.installedPacks).get(), hasLength(1));
  });

  test('three mismatches fail the install with nothing registered', () async {
    final url = clipUrl(2, 'intro', 1);
    downloader.corruptTimes[url] = 3;

    await expectLater(install(), throwsA(isA<PackInstallException>()));

    expect(downloader.calls.where((u) => u == url), hasLength(3));
    expect(await db.select(db.installedPacks).get(), isEmpty);
    expect(await db.select(db.localTracks).get(), isEmpty);
    expect(fileExists('packs/golden-era/v1/2-intro.mp3'), isFalse);
  });

  test('an interrupted install leaves the previous version intact', () async {
    await install(version: 1);

    downloader.failing.add(clipUrl(2, 'middle', 2));
    await expectLater(install(version: 2), throwsA(isA<PackInstallException>()));

    final pack = await db.select(db.installedPacks).getSingle();
    expect(pack.version, 1);
    final tracks = await db.select(db.localTracks).get();
    expect(tracks, hasLength(3));
    for (final t in tracks) {
      expect(t.introPath, contains('/v1/'));
      expect(fileExists(t.introPath!), isTrue);
      expect(fileExists(t.middlePath!), isTrue);
    }
  });

  test('a successful upgrade replaces the rows and deletes the old folder', () async {
    await install(version: 1);
    await install(version: 2, tracks: 2);

    final pack = await db.select(db.installedPacks).getSingle();
    expect(pack.version, 2);
    final tracks = await db.select(db.localTracks).get();
    expect(tracks, hasLength(2));
    expect(tracks.every((t) => t.introPath!.contains('/v2/')), isTrue);
    expect(Directory(p.join(base.path, 'packs', 'golden-era', 'v1')).existsSync(), isFalse);
    expect(fileExists('packs/golden-era/v2/1-intro.mp3'), isTrue);
  });

  test('files that already verify are not downloaded again', () async {
    final url = clipUrl(1, 'intro', 1);
    final file = File(p.join(base.path, 'packs/golden-era/v1/1-intro.mp3'));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bodyFor(url));

    await install();

    expect(downloader.calls, isNot(contains(url)));
    expect(downloader.calls, hasLength(5));
    expect(await db.select(db.installedPacks).get(), hasLength(1));
  });

  test('a corrupt leftover file is replaced', () async {
    final url = clipUrl(1, 'intro', 1);
    final file = File(p.join(base.path, 'packs/golden-era/v1/1-intro.mp3'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('half a file');

    await install();

    expect(downloader.calls, contains(url));
    expect(file.readAsBytesSync(), bodyFor(url));
  });

  test('reports progress through to installed', () async {
    final seen = <PackInstallProgress>[];
    final sub = installer.progressFor('golden-era').listen(seen.add);

    await install();
    await pumpEventQueue();
    await sub.cancel();

    final states = seen.map((e) => e.state).toSet();
    expect(states, containsAll([
      PackInstallState.queued,
      PackInstallState.downloading,
      PackInstallState.installed,
    ]));
    final last = seen.last;
    expect(last.state, PackInstallState.installed);
    expect(last.filesDone, 6);
    expect(last.filesTotal, 6);
    expect(last.bytesDone, last.bytesTotal);
  });

  test('reports a failed install with its error', () async {
    downloader.failing.add(clipUrl(1, 'intro', 1));
    final seen = <PackInstallProgress>[];
    final sub = installer.progressFor('golden-era').listen(seen.add);

    await expectLater(install(), throwsA(isA<PackInstallException>()));
    await pumpEventQueue();
    await sub.cancel();

    expect(seen.last.state, PackInstallState.failed);
    expect(seen.last.error, contains('connection lost'));
  });

  group('installs of the same pack', () {
    test('run one after another, so the second finds the files verified', () async {
      await Future.wait([install(), install()]);

      expect(downloader.calls, hasLength(6), reason: 'each clip downloaded once');
      expect(downloader.maxRunning, lessThanOrEqualTo(4));
      expect(await db.select(db.installedPacks).get(), hasLength(1));
      expect(await db.select(db.localTracks).get(), hasLength(3));
    });

    test('keep going after one fails', () async {
      // The first install uses up the 3 corrupt downloads and fails. The second,
      // queued behind it, then gets good bytes. Run at once, they would share them.
      downloader.corruptTimes[clipUrl(1, 'intro', 1)] = 3;
      final first = install();
      final second = install();

      await expectLater(first, throwsA(isA<PackInstallException>()));
      await second;
      expect((await db.select(db.installedPacks).getSingle()).version, 1);
    });
  });

  group('a manifest that is not the one asked for', () {
    test('another slug is refused before anything is downloaded', () async {
      final json = manifestJson(slug: 'other-pack');
      await expectLater(
        installer.install(manifestOf(json), json, expectedSlug: 'golden-era', expectedVersion: 1),
        throwsA(isA<PackInstallException>()),
      );
      expect(downloader.calls, isEmpty);
      expect(await db.select(db.installedPacks).get(), isEmpty);
    });

    test('another version is refused', () async {
      final json = manifestJson(version: 2);
      await expectLater(
        installer.install(manifestOf(json), json, expectedSlug: 'golden-era', expectedVersion: 3),
        throwsA(isA<PackInstallException>()),
      );
      expect(downloader.calls, isEmpty);
    });

    test('is reported as a failed install of the pack that was asked for', () async {
      final seen = <PackInstallProgress>[];
      final sub = installer.progressFor('golden-era').listen(seen.add);
      final json = manifestJson(slug: 'other-pack');
      await expectLater(
        installer.install(manifestOf(json), json, expectedSlug: 'golden-era', expectedVersion: 1),
        throwsA(isA<PackInstallException>()),
      );
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.single.state, PackInstallState.failed);
      expect(seen.single.error, contains('other-pack'));
    });

    test('a slug that is not a valid pack slug is refused even when it was asked for', () async {
      // The parser refuses such a slug. The installer checks again, because the
      // slug becomes part of file paths and of a recursive delete.
      final m = manifestOf(manifestJson());
      final bad = PackManifest(
        slug: '../..',
        version: 1,
        publishedAt: m.publishedAt,
        nameAm: m.nameAm,
        nameEn: m.nameEn,
        tracks: m.tracks,
        totalBytes: m.totalBytes,
      );
      await expectLater(
        installer.install(bad, '{}', expectedSlug: '../..', expectedVersion: 1),
        throwsA(isA<PackInstallException>()),
      );
      expect(downloader.calls, isEmpty);
    });
  });

  test('an upgrade still succeeds when the old folder cannot be removed', () async {
    final stubborn = PackInstaller(
      db: db,
      downloader: downloader,
      supportDirectory: () async => base,
      deleteDirectory: (_) async => throw const FileSystemException('busy'),
    );
    addTearDown(stubborn.dispose);
    final seen = <PackInstallProgress>[];
    final sub = stubborn.progressFor('golden-era').listen(seen.add);

    final v1 = manifestJson(version: 1);
    await stubborn.install(manifestOf(v1), v1, expectedSlug: 'golden-era', expectedVersion: 1);
    final v2 = manifestJson(version: 2);
    await stubborn.install(manifestOf(v2), v2, expectedSlug: 'golden-era', expectedVersion: 2);
    await pumpEventQueue();
    await sub.cancel();

    expect((await db.select(db.installedPacks).getSingle()).version, 2);
    expect(seen.last.state, PackInstallState.installed);
  });

  test('the stored paths are where the files were downloaded', () async {
    await install();
    final downloaded = downloader.calls.toSet();
    for (final t in await db.select(db.localTracks).get()) {
      expect(fileExists(t.introPath!), isTrue);
      expect(fileExists(t.middlePath!), isTrue);
      expect(downloaded, contains(clipUrl(t.id, 'intro', 1)));
    }
  });

  test('a late subscriber gets the latest state first', () async {
    await install();
    final first = await installer.progressFor('golden-era').first;
    expect(first.state, PackInstallState.installed);
  });

  group('reusing clips already on the phone', () {
    Future<void> cache(int trackId, ClipKind kind, List<int> bytes) async {
      final path = ClipStore.streamPath(trackId, kind);
      File(p.join(base.path, path))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      await db.into(db.clips).insert(
            ClipsCompanion.insert(
              trackId: trackId,
              kind: kind.name,
              path: path,
              bytes: bytes.length,
              source: ClipSource.stream,
              lastPlayedAt: 1,
            ),
          );
    }

    test('a clip cached from streaming is copied into the pack, not downloaded again', () async {
      final url = clipUrl(2, 'intro', 1);
      await cache(2, ClipKind.intro, bodyFor(url));

      await install();

      expect(downloader.calls, isNot(contains(url)));
      expect(downloader.calls, hasLength(5));
      final row = await (db.select(db.clips)..where((c) => c.trackId.equals(2) & c.kind.equals('intro'))).getSingle();
      expect((row.source, row.path), (ClipSource.pack, 'packs/golden-era/v1/2-intro.mp3'));
      expect(fileExists('packs/golden-era/v1/2-intro.mp3'), isTrue);
      expect(fileExists(ClipStore.streamPath(2, ClipKind.intro)), isFalse);
    });

    test('a cached clip that does not match the manifest is downloaded', () async {
      final url = clipUrl(2, 'intro', 1);
      await cache(2, ClipKind.intro, [1, 2, 3]);

      await install();

      expect(downloader.calls, contains(url));
      expect(await fileHasBytes('packs/golden-era/v1/2-intro.mp3', bodyFor(url)), isTrue);
    });
  });

  group('cancel', () {
    test('stops the install before its files, and registers nothing', () async {
      final events = <PackInstallProgress>[];
      final sub = installer.progressFor('golden-era').listen(events.add);
      addTearDown(sub.cancel);

      final run = install();
      installer.cancel('golden-era');

      await expectLater(
        run,
        throwsA(isA<PackInstallException>().having((e) => e.failure, 'failure', PackInstallFailure.cancelled)),
      );
      expect(downloader.calls, isEmpty);
      expect(await db.select(db.installedPacks).get(), isEmpty);
      expect(await db.select(db.clips).get(), isEmpty);
      await pumpEventQueue();
      expect(events.last.state, PackInstallState.cancelled);
      expect(events.last.isTerminal, isTrue);
    });

    test('a cancelled update leaves the installed version playable', () async {
      await install(version: 1);
      final run = install(version: 2);
      installer.cancel('golden-era');
      await expectLater(run, throwsA(isA<PackInstallException>()));

      expect(await installer.installedVersion('golden-era'), 1);
      final clips = await db.select(db.clips).get();
      expect(clips, hasLength(6));
      expect(clips.every((c) => fileExists(c.path)), isTrue);
    });

    test('does not reach the next install of the same pack', () async {
      final first = install();
      installer.cancel('golden-era');
      await expectLater(first, throwsA(isA<PackInstallException>()));

      await install();
      expect(await installer.installedVersion('golden-era'), 1);
    });
  });

  group('remove', () {
    test('drops the pack and moves its clips into the stream cache, keeping when they were played', () async {
      await install();
      await (db.update(db.clips)..where((c) => c.trackId.equals(1)))
          .write(const ClipsCompanion(lastPlayedAt: Value(42)));

      await installer.remove('golden-era');

      expect(await db.select(db.installedPacks).get(), isEmpty);
      expect(await db.select(db.localTracks).get(), isEmpty);
      final clips = await db.select(db.clips).get();
      expect(clips, hasLength(6));
      for (final c in clips) {
        expect(c.source, ClipSource.stream);
        expect(c.path, ClipStore.streamPath(c.trackId, ClipKind.values.byName(c.kind)));
        expect(fileExists(c.path), isTrue);
      }
      expect(clips.where((c) => c.trackId == 1).map((c) => c.lastPlayedAt), everyElement(42));
      expect(Directory(p.join(base.path, 'packs', 'golden-era')).existsSync(), isFalse);
      // The catalog still knows the tracks, so they can be streamed again.
      expect(await db.select(db.catalogTracks).get(), hasLength(3));
    });

    test('a clip another installed pack has stays a pack clip there', () async {
      final other = manifestJson(slug: 'other-pack', tracks: 2);
      await installer.install(manifestOf(other), other, expectedSlug: 'other-pack', expectedVersion: 1);
      await install(tracks: 3);

      await installer.remove('golden-era');

      final clips = await db.select(db.clips).get();
      expect(
        clips.where((c) => c.trackId != 3).map((c) => (c.source, c.path)),
        everyElement(isA<(String, String)>().having((r) => r.$1, 'source', ClipSource.pack)
            .having((r) => r.$2, 'path', startsWith('packs/other-pack/v1/'))),
      );
      expect(clips.where((c) => c.trackId == 3).map((c) => c.source), everyElement(ClipSource.stream));
      expect(await installer.installedVersion('other-pack'), 1);
    });
  });

  group('downloads under way', () {
    test('cancel stops them as well, and the install ends as cancelled', () async {
      downloader.hold = Completer<void>();
      addTearDown(() => downloader.hold!.isCompleted ? null : downloader.hold!.complete());
      final run = install();
      // Let the first downloads start and wait.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(downloader.calls, isNotEmpty);

      installer.cancel('golden-era');

      await expectLater(
        run,
        throwsA(isA<PackInstallException>().having((e) => e.failure, 'failure', PackInstallFailure.cancelled)),
      );
      expect(downloader.cancelledGroups, ['pack:golden-era']);
      expect(await db.select(db.installedPacks).get(), isEmpty);
    });

    test('carry the pack\'s group and the Wi-Fi rule', () async {
      final json = manifestJson();
      await installer.install(manifestOf(json), json, expectedSlug: 'golden-era', expectedVersion: 1, wifiOnly: true);
      expect(downloader.groups.values.toSet(), {'pack:golden-era'});
      expect(downloader.wifiOnly.values.toSet(), {true});
    });

    test('a full phone fails the install as storage full, with what was still to come', () async {
      downloader.noSpace.add(clipUrl(3, 'middle', 1));
      await expectLater(
        install(),
        throwsA(isA<PackInstallException>()
            .having((e) => e.failure, 'failure', PackInstallFailure.storageFull)
            .having((e) => e.missingBytes, 'missingBytes', greaterThan(0))),
      );
    });
  });

  group('built-in clips', () {
    Future<void> builtIn(int trackId, ClipKind kind) async {
      final path = ClipStore.starterPath(trackId, kind);
      File(p.join(base.path, path))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bodyFor(clipUrl(trackId, kind.name, 1)));
      await db.into(db.clips).insert(
            ClipsCompanion.insert(
              trackId: trackId,
              kind: kind.name,
              path: path,
              bytes: 1,
              source: ClipSource.starter,
              lastPlayedAt: 1,
            ),
          );
    }

    test('stay built in when a pack has the same track, and when the pack is removed', () async {
      await builtIn(2, ClipKind.intro);

      await install();
      var clip = await (db.select(db.clips)..where((c) => c.trackId.equals(2) & c.kind.equals('intro'))).getSingle();
      expect((clip.source, clip.path), (ClipSource.starter, ClipStore.starterPath(2, ClipKind.intro)));
      // Neither downloaded nor copied into the pack: the built-in file is the one that plays.
      expect(downloader.calls, isNot(contains(clipUrl(2, 'intro', 1))));
      expect(fileExists('packs/golden-era/v1/2-intro.mp3'), isFalse);

      await installer.remove('golden-era');
      clip = await (db.select(db.clips)..where((c) => c.trackId.equals(2) & c.kind.equals('intro'))).getSingle();
      expect((clip.source, clip.path), (ClipSource.starter, ClipStore.starterPath(2, ClipKind.intro)));
      expect(fileExists(clip.path), isTrue);
    });
  });

  test('a clip prefetched earlier stays playable until the pack is in, then is removed', () async {
    final url = clipUrl(1, 'intro', 1);
    final streamPath = ClipStore.streamPath(1, ClipKind.intro);
    File(p.join(base.path, streamPath))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bodyFor(url));
    await db.into(db.clips).insert(
          ClipsCompanion.insert(
            trackId: 1,
            kind: 'intro',
            path: streamPath,
            bytes: 1,
            source: ClipSource.stream,
            lastPlayedAt: 1,
          ),
        );
    // Copied, not moved: a game may be playing it while the pack downloads.
    downloader.hold = Completer<void>();
    final run = install();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fileExists(streamPath), isTrue);
    expect(fileExists('packs/golden-era/v1/1-intro.mp3'), isTrue);
    downloader.hold!.complete();
    await run;
    expect(downloader.calls, isNot(contains(url)));
    expect(fileExists(streamPath), isFalse);
  });

  test('a cancelled install leaves a prefetched clip where it was', () async {
    final streamPath = ClipStore.streamPath(1, ClipKind.intro);
    File(p.join(base.path, streamPath))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bodyFor(clipUrl(1, 'intro', 1)));
    await db.into(db.clips).insert(
          ClipsCompanion.insert(
            trackId: 1,
            kind: 'intro',
            path: streamPath,
            bytes: 1,
            source: ClipSource.stream,
            lastPlayedAt: 1,
          ),
        );
    downloader.hold = Completer<void>();
    addTearDown(() => downloader.hold!.isCompleted ? null : downloader.hold!.complete());
    final run = install();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    installer.cancel('golden-era');
    await expectLater(run, throwsA(isA<PackInstallException>()));

    final row = await (db.select(db.clips)..where((c) => c.trackId.equals(1))).getSingle();
    expect((row.source, row.path), (ClipSource.stream, streamPath));
    expect(fileExists(streamPath), isTrue);
  });

  test('removing a pack waits for the game in progress to end', () async {
    final store = ClipStore(db: db, supportDirectory: () async => base);
    final guarded = PackInstaller(db: db, downloader: downloader, supportDirectory: () async => base, store: store);
    addTearDown(guarded.dispose);
    final json = manifestJson();
    await guarded.install(manifestOf(json), json, expectedSlug: 'golden-era', expectedVersion: 1);

    store.sessionStarted();
    var removed = false;
    final removal = guarded.remove('golden-era').then((_) => removed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(removed, isFalse);
    expect(fileExists('packs/golden-era/v1/1-intro.mp3'), isTrue);

    await store.sessionEnded(capBytes: 1 << 30);
    await removal;
    expect(await db.select(db.installedPacks).get(), isEmpty);
  });
}
