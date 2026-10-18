import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/l10n/display_name.dart';
import 'package:yeman_zefen/features/game/data/game_library.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';

LocalTrack row({
  String pack = 'golden-era',
  int id = 1,
  String? titleAm = 'ዘፈን',
  String? titleLatin = 'Song',
  String? artistAm = 'ድምፃዊ',
  String? artistLatin = 'Artist',
  int? artistId = 7,
  int? generationId = 2,
  String? intro = 'packs/golden-era/v1/1-intro.mp3',
  String? middle = 'packs/golden-era/v1/1-middle.mp3',
}) =>
    LocalTrack(
      packSlug: pack,
      id: id,
      titleAm: titleAm,
      titleLatin: titleLatin,
      artistAm: artistAm,
      artistLatin: artistLatin,
      artistId: artistId,
      generationId: generationId,
      introPath: intro,
      middlePath: middle,
    );

void main() {
  final base = Directory('/data/support');

  test('turns rows into tracks for the engine', () {
    final lib = GameLibrary.fromRows([row(id: 1), row(id: 2, artistId: 8, generationId: null)], base);

    expect(lib.tracks.map((t) => (t.id, t.artistId, t.generationId)), [(1, 7, 2), (2, 8, null)]);
    expect(lib.eras, {2});
  });

  test('a track in two packs is kept once', () {
    final lib = GameLibrary.fromRows([row(pack: 'a'), row(pack: 'b')], base);
    expect(lib.tracks, hasLength(1));
  });

  test('leaves out rows from before schema 2, which have no artist id', () {
    final lib = GameLibrary.fromRows([row(id: 1, artistId: null), row(id: 2)], base);
    expect(lib.tracks.map((t) => t.id), [2]);
    expect(lib.isEmpty, isFalse);
    expect(GameLibrary.fromRows([row(artistId: null)], base).isEmpty, isTrue);
  });

  group('clip paths', () {
    final lib = GameLibrary.fromRows([row()], base);

    test('are absolute, from the support directory', () {
      expect(lib.clipPath(1, GameMode.intro), p.join('/data/support', 'packs/golden-era/v1/1-intro.mp3'));
      expect(lib.clipPath(1, GameMode.middle), p.join('/data/support', 'packs/golden-era/v1/1-middle.mp3'));
    });

    test('are null for an unknown track or a clip the track does not have', () {
      expect(lib.clipPath(99, GameMode.intro), isNull);
      final partial = GameLibrary.fromRows([row(middle: null)], base);
      expect(partial.clipPath(1, GameMode.middle), isNull);
      expect(partial.clipPath(1, GameMode.intro), isNotNull);
    });
  });

  group('names', () {
    test('keep both scripts, for the screen to pick from', () {
      final lib = GameLibrary.fromRows([row()], base);
      expect(lib.trackName(1), const DisplayName(am: 'ዘፈን', latin: 'Song'));
      expect(lib.artistName(7), const DisplayName(am: 'ድምፃዊ', latin: 'Artist'));
    });

    test('keep only the script the catalog has', () {
      final lib = GameLibrary.fromRows([
        row(id: 1, titleAm: null, titleLatin: 'Only Latin'),
        row(id: 2, titleAm: 'ብቻ', titleLatin: null),
        row(id: 3, titleAm: ' ', titleLatin: 'Blank Fidel'),
      ], base);
      expect(lib.trackName(1), const DisplayName(latin: 'Only Latin'));
      expect(lib.trackName(2), const DisplayName(am: 'ብቻ'));
      expect(lib.trackName(3), const DisplayName(latin: 'Blank Fidel'));
    });

    test('are empty when a track has no name, for the screen to say "Unknown"', () {
      final lib = GameLibrary.fromRows([row(titleAm: null, titleLatin: null, artistAm: null, artistLatin: null)], base);
      expect(lib.trackName(1).isEmpty, isTrue);
      expect(lib.artistName(7).isEmpty, isTrue);
      expect(lib.trackName(99).isEmpty, isTrue);
    });

    test('an artist takes the name from the first track that has one', () {
      final lib = GameLibrary.fromRows([
        row(id: 1, artistAm: null, artistLatin: null),
        row(id: 2, artistAm: 'ስም', artistLatin: 'Name'),
      ], base);
      expect(lib.artistName(7), const DisplayName(am: 'ስም', latin: 'Name'));
    });
  });

  test('loads the installed tracks from the database', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.localTracks).insert(
          LocalTracksCompanion.insert(
            packSlug: 'golden-era',
            id: 5,
            artistId: const Value(7),
            generationId: const Value(3),
            introPath: const Value('packs/golden-era/v1/5-intro.mp3'),
          ),
        );

    final lib = await loadGameLibrary(db, base);

    expect(lib.tracks.single.id, 5);
    expect(lib.eras, {3});
    expect(lib.clipPath(5, GameMode.intro), endsWith('5-intro.mp3'));
  });
}
