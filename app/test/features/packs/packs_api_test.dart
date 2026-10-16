import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
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
      api: ApiClient(
        baseUrl: 'https://api.test',
        idToken: ({bool forceRefresh = false}) async => 'tok',
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({'packs': [listing]}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
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
      api: _apiReturning(200, '{}'),
      cdnClient: MockClient((_) async => http.Response('{"schema":1}', 200)),
    );
    expect(await api.fetchManifestJson('https://cdn.test/m.json'), '{"schema":1}');
  });

  test('a manifest fetch that is not 200 throws', () async {
    final api = PacksApi(
      api: _apiReturning(200, '{}'),
      cdnClient: MockClient((_) async => http.Response('nope', 503)),
    );
    await expectLater(api.fetchManifestJson('https://cdn.test/m.json'), throwsA(isA<PacksApiException>()));
  });

  test('the ID token goes to the API but never to the CDN', () async {
    String? apiAuth;
    String? cdnAuth;
    final api = PacksApi(
      api: ApiClient(
        baseUrl: 'https://api.test',
        idToken: ({bool forceRefresh = false}) async => 'tok',
        client: MockClient((request) async {
          apiAuth = request.headers['Authorization'];
          return http.Response('{"packs":[]}', 200);
        }),
      ),
      cdnClient: MockClient((request) async {
        cdnAuth = request.headers['Authorization'];
        return http.Response('{}', 200);
      }),
    );
    await api.listPacks();
    await api.fetchManifestJson('https://cdn.test/m.json');
    expect(apiAuth, 'Bearer tok');
    expect(cdnAuth, isNull);
  });

  test('a failed /v1/packs call throws a typed ApiException', () async {
    final api = PacksApi(api: _apiReturning(503, '{"error":{"code":"unavailable","message":"down"}}'));
    await expectLater(api.listPacks(), throwsA(isA<ServerException>()));
  });
}

ApiClient _apiReturning(int status, String body) => ApiClient(
  baseUrl: 'https://api.test',
  idToken: ({bool forceRefresh = false}) async => 'tok',
  client: MockClient((_) async => http.Response(body, status)),
);
