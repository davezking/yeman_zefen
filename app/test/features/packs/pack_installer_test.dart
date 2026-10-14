import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/data/pack_installer.dart';
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
    return installer.install(manifestOf(json), json);
  }

  bool fileExists(String relative) => File(p.join(base.path, relative)).existsSync();

  test('downloads, verifies and registers every track', () async {
    await install();

    final pack = await db.select(db.installedPacks).getSingle();
    expect(pack.slug, 'golden-era');
    expect(pack.version, 1);
    expect(pack.manifestJson, manifestJson());

    final tracks = await db.select(db.localTracks).get();
    expect(tracks, hasLength(3));
    for (final t in tracks) {
      expect(t.introPath, 'packs/golden-era/v1/${t.id}-intro.mp3');
      expect(t.middlePath, 'packs/golden-era/v1/${t.id}-middle.mp3');
      expect(fileExists(t.introPath!), isTrue);
      expect(fileExists(t.middlePath!), isTrue);
    }
    expect(await installer.installedVersion('golden-era'), 1);
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

  test('a late subscriber gets the latest state first', () async {
    await install();
    final first = await installer.progressFor('golden-era').first;
    expect(first.state, PackInstallState.installed);
  });
}
