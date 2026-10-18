import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../../tool/fetch_starter_pack.dart';
import '../features/packs/starter_fixtures.dart';

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('fetch_starter_test'));
  tearDown(() => out.deleteSync(recursive: true));

  const api = 'https://api.test';

  // The manifest has Amharic names, so the body is UTF-8 bytes.
  http.Response json(Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  /// Serves `/v1/packs`, the manifest and the clips of [manifest].
  http.Client server({
    Map<String, dynamic>? manifest,
    String slug = 'starter',
    Set<String> failing = const {},
    Set<String> damaged = const {},
  }) {
    final m = manifest ?? starterManifestMap(tracks: 4);
    return MockClient((request) async {
      final url = request.url.toString();
      if (failing.contains(url)) return http.Response('no', 500);
      if (url == '$api/v1/packs') {
        return json({
          'packs': [
            {'slug': slug, 'manifestUrl': 'https://cdn.test/packs/starter/v1/manifest.json'},
            {'slug': 'other', 'manifestUrl': 'https://cdn.test/packs/other/v1/manifest.json'},
          ],
        });
      }
      if (url == 'https://cdn.test/packs/starter/v1/manifest.json') return json(m);
      final match = RegExp(r'clips/(\d+)-(intro|middle)\.mp3$').firstMatch(url);
      if (match != null) {
        final body = starterBody(int.parse(match.group(1)!), match.group(2)!);
        return http.Response.bytes(damaged.contains(url) ? [...body, 1] : body, 200);
      }
      return http.Response('not found', 404);
    });
  }

  Future<StarterFetchResult> fetch(http.Client client) =>
      fetchStarterPack(client: client, apiBase: api, outDir: out);

  test('writes the manifest and every clip, in the layout the app reads', () async {
    final result = await fetch(server());

    expect(result.tracks, 4);
    expect(result.version, 1);
    final manifest = jsonDecode(File(p.join(out.path, 'manifest.json')).readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['slug'], 'starter');
    for (var id = 1; id <= 4; id++) {
      for (final kind in ['intro', 'middle']) {
        expect(File(p.join(out.path, 'clips', '$id-$kind.mp3')).readAsBytesSync(), starterBody(id, kind));
      }
    }
    expect(result.bytes, 4 * (starterBody(1, 'intro').length + starterBody(1, 'middle').length));
    expect(result.fitsInRepository, isTrue);
  });

  test('says when the pack is over 10 MB, so it is not committed', () {
    const big = StarterFetchResult(version: 1, tracks: 25, bytes: starterCommitLimitBytes + 1);
    expect(big.fitsInRepository, isFalse);
    expect(const StarterFetchResult(version: 1, tracks: 25, bytes: starterCommitLimitBytes).fitsInRepository, isTrue);
  });

  test('replaces an earlier fetch: clips the new pack does not have are removed', () async {
    File(p.join(out.path, 'clips', '99-intro.mp3'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    File(p.join(out.path, 'clips', '.gitkeep')).createSync();

    await fetch(server());

    expect(File(p.join(out.path, 'clips', '99-intro.mp3')).existsSync(), isFalse);
    expect(File(p.join(out.path, 'clips', '.gitkeep')).existsSync(), isTrue);
  });

  test('a clip that fails its checksum stops the run and writes nothing', () async {
    await expectLater(
      fetch(server(damaged: {'https://cdn.test/clips/3-middle.mp3'})),
      throwsA(isA<StarterFetchException>().having((e) => e.message, 'message', contains('checksum'))),
    );
    expect(out.listSync(), isEmpty);
  });

  test('a failed download stops the run and leaves the folder as it was', () async {
    File(p.join(out.path, 'manifest.json')).writeAsStringSync('old');

    await expectLater(
      fetch(server(failing: {'https://cdn.test/clips/2-intro.mp3'})),
      throwsA(isA<StarterFetchException>()),
    );
    expect(File(p.join(out.path, 'manifest.json')).readAsStringSync(), 'old');
  });

  test('a missing starter pack is an error that says so', () async {
    await expectLater(
      fetch(server(slug: 'golden-era')),
      throwsA(isA<StarterFetchException>().having((e) => e.message, 'message', contains('starter'))),
    );
  });

  test('a manifest the app cannot use is refused', () async {
    final bad = starterManifestMap()..['schema'] = 2;
    await expectLater(fetch(server(manifest: bad)), throwsA(isA<StarterFetchException>()));
    expect(out.listSync(), isEmpty);
  });
}
