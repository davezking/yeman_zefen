import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Deterministic bytes of a starter clip.
List<int> starterBody(int trackId, String kind) => utf8.encode('starter:$trackId:$kind');

/// An asset bundle that serves a fixed map and throws for anything else, like a build that does
/// not contain the asset.
class MapAssetBundle extends CachingAssetBundle {
  MapAssetBundle(this.files);

  final Map<String, List<int>> files;

  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// A `starter` pack manifest as the pack builder writes it: [tracks] tracks, 6 artists (ids 101-106)
/// and two eras, so a session of 10 rounds with artist and song questions can be made from it.
Map<String, dynamic> starterManifestMap({int tracks = 12, int version = 1, Set<int> corrupt = const {}}) {
  Map<String, dynamic> clip(int id, String kind) {
    final body = starterBody(id, kind);
    return {
      'url': 'https://cdn.test/clips/$id-$kind.mp3',
      'sha256': sha256.convert(corrupt.contains(id) ? [...body, 0] : body).toString(),
      'bytes': body.length,
      'lengthMs': 10000,
    };
  }

  final list = [
    for (var id = 1; id <= tracks; id++)
      {
        'id': id,
        'titleAm': 'ዘፈን $id',
        'titleLatin': 'Song $id',
        'artistId': 100 + id % 6 + 1,
        'artistAm': 'ድምፃዊ ${id % 6 + 1}',
        'artistLatin': 'Artist ${id % 6 + 1}',
        'generationId': 1 + id % 2,
        'genreIds': <int>[],
        'releaseYear': 1980,
        'clips': {'intro': clip(id, 'intro'), 'middle': clip(id, 'middle')},
      },
  ];
  var total = 0;
  for (final t in list) {
    for (final c in (t['clips']! as Map<String, dynamic>).values) {
      total += (c as Map<String, dynamic>)['bytes']! as int;
    }
  }
  return {
    'schema': 1,
    'slug': 'starter',
    'version': version,
    'publishedAt': 1760000000000,
    'names': {'am': 'መነሻ', 'en': 'Starter'},
    'generationId': null,
    'genreId': null,
    'tracks': list,
    'totalBytes': total,
  };
}

/// The bundle the app would ship: `assets/starter/manifest.json` and `clips/{id}-{kind}.mp3`.
MapAssetBundle starterBundle({int tracks = 12, int version = 1, Set<int> corrupt = const {}}) {
  final manifest = starterManifestMap(tracks: tracks, version: version, corrupt: corrupt);
  return MapAssetBundle({
    'assets/starter/manifest.json': utf8.encode(jsonEncode(manifest)),
    for (var id = 1; id <= tracks; id++)
      for (final kind in ['intro', 'middle']) 'assets/starter/clips/$id-$kind.mp3': starterBody(id, kind),
  });
}
