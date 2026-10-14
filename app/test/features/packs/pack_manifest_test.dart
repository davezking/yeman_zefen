import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/packs/data/pack_manifest.dart';

import 'pack_fixtures.dart';

void main() {
  test('parses a valid manifest', () {
    final m = PackManifest.parse(manifestJson(tracks: 2));
    expect(m.slug, 'golden-era');
    expect(m.version, 1);
    expect(m.nameEn, 'Golden era');
    expect(m.tracks, hasLength(2));
    expect(m.tracks.first.titleAm, 'ዘፈን 1');
    expect(m.tracks.first.intro.sha256, hasLength(64));
    expect(m.tracks.first.artistId, 7);
    expect(m.tracks.first.generationId, 2);
    expect(m.totalBytes, greaterThan(0));
  });

  test('accepts null titles and year', () {
    final map = manifestMap(tracks: 1);
    final track = (map['tracks'] as List).first as Map<String, dynamic>;
    track['titleAm'] = null;
    track['titleLatin'] = null;
    track['releaseYear'] = null;
    final m = PackManifest.parse(jsonEncode(map));
    expect(m.tracks.single.titleAm, isNull);
    expect(m.tracks.single.releaseYear, isNull);
  });

  test('accepts a track with no era', () {
    final map = manifestMap(tracks: 1);
    ((map['tracks'] as List).first as Map<String, dynamic>)['generationId'] = null;
    expect(PackManifest.parse(jsonEncode(map)).tracks.single.generationId, isNull);
  });

  test('rejects a track with no artist id', () {
    final map = manifestMap(tracks: 1);
    ((map['tracks'] as List).first as Map<String, dynamic>).remove('artistId');
    expect(() => PackManifest.parse(jsonEncode(map)), throwsA(isA<PackManifestException>()));
  });

  test('rejects a slug that could leave the packs folder', () {
    for (final slug in ['../..', 'a/b', 'Golden-Era', 'golden_era', '-golden', 'golden--era', '', 'x' * 61]) {
      final map = manifestMap()..['slug'] = slug;
      expect(() => PackManifest.parse(jsonEncode(map)), throwsA(isA<PackManifestException>()), reason: slug);
    }
  });

  test('accepts the slugs the admin API accepts', () {
    for (final slug in ['golden-era', 'a', '90s', 'pack-2-x', 'x' * 60]) {
      final map = manifestMap()..['slug'] = slug;
      expect(PackManifest.parse(jsonEncode(map)).slug, slug);
    }
  });

  test('ignores unknown fields', () {
    final map = manifestMap(tracks: 1)..['somethingNew'] = true;
    expect(() => PackManifest.parse(jsonEncode(map)), returnsNormally);
  });

  test('rejects a clip with no checksum', () {
    final map = manifestMap(tracks: 1);
    final clips = ((map['tracks'] as List).first as Map)['clips'] as Map<String, dynamic>;
    (clips['intro'] as Map<String, dynamic>).remove('sha256');
    expect(
      () => PackManifest.parse(jsonEncode(map)),
      throwsA(isA<PackManifestException>().having((e) => e.message, 'message', contains('sha256'))),
    );
  });

  test('rejects a malformed checksum', () {
    final map = manifestMap(tracks: 1);
    final clips = ((map['tracks'] as List).first as Map)['clips'] as Map<String, dynamic>;
    (clips['middle'] as Map<String, dynamic>)['sha256'] = 'ABC';
    expect(() => PackManifest.parse(jsonEncode(map)), throwsA(isA<PackManifestException>()));
  });

  test('rejects an unknown schema', () {
    final map = manifestMap()..['schema'] = 2;
    expect(
      () => PackManifest.parse(jsonEncode(map)),
      throwsA(isA<PackManifestException>().having((e) => e.message, 'message', contains('schema'))),
    );
  });

  test('rejects a missing schema', () {
    final map = manifestMap()..remove('schema');
    expect(() => PackManifest.parse(jsonEncode(map)), throwsA(isA<PackManifestException>()));
  });

  test('rejects totalBytes that do not match the clips', () {
    final map = manifestMap()..['totalBytes'] = 1;
    expect(() => PackManifest.parse(jsonEncode(map)), throwsA(isA<PackManifestException>()));
  });

  test('rejects a track listed twice', () {
    final map = manifestMap(tracks: 2);
    final tracks = map['tracks'] as List;
    (tracks[1] as Map<String, dynamic>)['id'] = 1;
    expect(() => PackManifest.parse(jsonEncode(map)), throwsA(isA<PackManifestException>()));
  });

  test('rejects an empty track list', () {
    final map = manifestMap()
      ..['tracks'] = <Object>[]
      ..['totalBytes'] = 0;
    expect(() => PackManifest.parse(jsonEncode(map)), throwsA(isA<PackManifestException>()));
  });

  test('rejects text that is not JSON', () {
    expect(() => PackManifest.parse('<html>'), throwsA(isA<PackManifestException>()));
  });
}
