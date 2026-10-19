import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/l10n/display_name.dart';
import 'package:yeman_zefen/features/game/data/game_library.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

CatalogTrack row({
  int id = 1,
  String? titleAm = 'ዘፈን',
  String? titleLatin = 'Song',
  String? artistAm = 'ድምፃዊ',
  String? artistLatin = 'Artist',
  int artistId = 7,
  int? generationId = 2,
  String? introUrl = 'https://cdn.test/1-intro.mp3',
  String? middleUrl = 'https://cdn.test/1-middle.mp3',
}) =>
    CatalogTrack(
      id: id,
      titleAm: titleAm,
      titleLatin: titleLatin,
      artistId: artistId,
      artistAm: artistAm,
      artistLatin: artistLatin,
      generationId: generationId,
      introUrl: introUrl,
      introSha256: introUrl == null ? null : 'a' * 64,
      introBytes: introUrl == null ? null : 100,
      middleUrl: middleUrl,
      middleSha256: middleUrl == null ? null : 'b' * 64,
      middleBytes: middleUrl == null ? null : 200,
      updatedAt: 1,
    );

Clip clip(int trackId, String kind, {String? path, String source = ClipSource.pack, bool broken = false}) => Clip(
      trackId: trackId,
      kind: kind,
      path: path ?? 'packs/golden-era/v1/$trackId-$kind.mp3',
      bytes: 100,
      source: source,
      lastPlayedAt: 1,
      broken: broken,
    );

void main() {
  final base = Directory('/data/support');

  test('turns rows into tracks for the engine', () {
    final lib = GameLibrary.fromRows([row(id: 1), row(id: 2, artistId: 8, generationId: null)], const [], base);

    expect(lib.tracks.map((t) => (t.id, t.artistId, t.generationId)), [(1, 7, 2), (2, 8, null)]);
    expect(lib.eras, {2});
  });

  test('a track listed twice is kept once', () {
    final lib = GameLibrary.fromRows([row(), row()], const [], base);
    expect(lib.tracks, hasLength(1));
  });

  test('an empty catalog is empty', () {
    expect(GameLibrary.fromRows(const [], const [], base).isEmpty, isTrue);
    expect(GameLibrary.fromRows([row()], const [], base).isEmpty, isFalse);
  });

  group('clips', () {
    final lib = GameLibrary.fromRows(
      [row(), row(id: 2, middleUrl: null, introUrl: null)],
      [clip(1, 'intro'), clip(2, 'middle')],
      base,
    );

    test('paths are absolute, from the support directory', () {
      expect(lib.clipPath(1, GameMode.intro), p.join('/data/support', 'packs/golden-era/v1/1-intro.mp3'));
    });

    test('are null for an unknown track or a clip that is not on the device', () {
      expect(lib.clipPath(99, GameMode.intro), isNull);
      expect(lib.clipPath(1, GameMode.middle), isNull);
      expect(lib.hasClip(1, GameMode.intro), isTrue);
      expect(lib.hasClip(1, GameMode.middle), isFalse);
    });

    test('the middle mode uses the middle clip', () {
      expect(lib.hasClip(2, GameMode.middle), isTrue);
      expect(lib.hasClip(2, GameMode.intro), isFalse);
    });

    test('a clip can be fetched when the catalog has its url, checksum and size', () {
      final remote = lib.remoteClip(1, GameMode.middle)!;
      expect(remote.url, 'https://cdn.test/1-middle.mp3');
      expect(remote.sha256, 'b' * 64);
      expect(remote.bytes, 200);
      expect(lib.remoteClip(2, GameMode.intro), isNull);
      expect(lib.remoteClip(99, GameMode.intro), isNull);
    });

    test('playable tracks: on the device, plus fetchable ones when downloads are allowed', () {
      expect(lib.playableIds(GameMode.intro, includeFetchable: false), {1});
      expect(lib.playableIds(GameMode.middle, includeFetchable: false), {2});
      expect(lib.playableIds(GameMode.intro, includeFetchable: true), {1});
      expect(lib.playableIds(GameMode.middle, includeFetchable: true), {1, 2});
    });
  });

  group('names', () {
    test('keep both scripts, for the screen to pick from', () {
      final lib = GameLibrary.fromRows([row()], const [], base);
      expect(lib.trackName(1), const DisplayName(am: 'ዘፈን', latin: 'Song'));
      expect(lib.artistName(7), const DisplayName(am: 'ድምፃዊ', latin: 'Artist'));
    });

    test('keep only the script the catalog has', () {
      final lib = GameLibrary.fromRows([
        row(id: 1, titleAm: null, titleLatin: 'Only Latin'),
        row(id: 2, titleAm: 'ብቻ', titleLatin: null),
        row(id: 3, titleAm: ' ', titleLatin: 'Blank Fidel'),
      ], const [], base);
      expect(lib.trackName(1), const DisplayName(latin: 'Only Latin'));
      expect(lib.trackName(2), const DisplayName(am: 'ብቻ'));
      expect(lib.trackName(3), const DisplayName(latin: 'Blank Fidel'));
    });

    test('are empty when a track has no name, for the screen to say "Unknown"', () {
      final lib = GameLibrary.fromRows([row(titleAm: null, titleLatin: null, artistAm: null, artistLatin: null)], const [], base);
      expect(lib.trackName(1).isEmpty, isTrue);
      expect(lib.artistName(7).isEmpty, isTrue);
      expect(lib.trackName(99).isEmpty, isTrue);
    });

    test('an artist takes the name from the first track that has one', () {
      final lib = GameLibrary.fromRows([
        row(id: 1, artistAm: null, artistLatin: null),
        row(id: 2, artistAm: 'ስም', artistLatin: 'Name'),
      ], const [], base);
      expect(lib.artistName(7), const DisplayName(am: 'ስም', latin: 'Name'));
    });
  });

  test('loads the catalog and the clips from the database', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.catalogTracks).insert(
          CatalogTracksCompanion.insert(
            id: const Value(5),
            artistId: 7,
            generationId: const Value(3),
            updatedAt: 1,
          ),
        );
    await db.into(db.clips).insert(
          ClipsCompanion.insert(
            trackId: 5,
            kind: 'intro',
            path: 'packs/golden-era/v1/5-intro.mp3',
            bytes: 10,
            source: ClipSource.pack,
            lastPlayedAt: 1,
          ),
        );

    final lib = await loadGameLibrary(db, base);

    expect(lib.tracks.single.id, 5);
    expect(lib.eras, {3});
    expect(lib.clipPath(5, GameMode.intro), endsWith('5-intro.mp3'));
    expect(lib.clipPath(5, GameMode.middle), isNull);
  });
}
