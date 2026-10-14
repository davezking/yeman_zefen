import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';

void main() {
  const listing = {
    'slug': 'golden-era',
    'names': {'am': 'ወርቃማ ዘመን', 'en': 'Golden era'},
    'generationId': 2,
    'genreId': null,
    'version': 3,
    'manifestUrl': 'https://cdn.test/packs/golden-era/v3/manifest.json',
    'trackCount': 120,
    'totalBytes': 19000000,
    'publishedAt': 1760000000000,
  };

  test('lists packs from /v1/packs', () async {
    late Uri requested;
    final api = PacksApi(
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({'packs': [listing]}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final packs = await api.listPacks();

    expect(requested.toString(), 'https://api.test/v1/packs');
    expect(packs.single.slug, 'golden-era');
    expect(packs.single.nameAm, 'ወርቃማ ዘመን');
    expect(packs.single.version, 3);
    expect(packs.single.manifestUrl, endsWith('/v3/manifest.json'));
  });

  test('fetches a manifest as raw text', () async {
    final api = PacksApi(
      baseUrl: 'https://api.test',
      client: MockClient((_) async => http.Response('{"schema":1}', 200)),
    );
    expect(await api.fetchManifestJson('https://cdn.test/m.json'), '{"schema":1}');
  });

  test('a non-200 response throws', () async {
    final api = PacksApi(
      baseUrl: 'https://api.test',
      client: MockClient((_) async => http.Response('nope', 503)),
    );
    await expectLater(api.listPacks(), throwsA(isA<PacksApiException>()));
  });
}
