import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/core/http/api_client.dart';

void main() {
  /// Token provider that hands out tok-1, then tok-2 after a forced refresh.
  ({IdTokenProvider provider, List<bool> refreshes}) tokens({String? first = 'tok-1'}) {
    final refreshes = <bool>[];
    return (
      provider: ({bool forceRefresh = false}) async {
        refreshes.add(forceRefresh);
        return forceRefresh ? 'tok-2' : first;
      },
      refreshes: refreshes,
    );
  }

  ApiClient clientFor(MockClientHandler handler, {IdTokenProvider? idToken}) => ApiClient(
    baseUrl: 'https://api.test/',
    idToken: idToken ?? tokens().provider,
    client: MockClient(handler),
  );

  test('sends the bearer token and joins the base URL and path', () async {
    late http.Request seen;
    final api = clientFor((r) async {
      seen = r;
      return http.Response('{"ok":true}', 200);
    });
    final body = await api.getJson('/v1/packs', query: {'a': 'b'});
    expect(seen.url.toString(), 'https://api.test/v1/packs?a=b');
    expect(seen.headers['Authorization'], 'Bearer tok-1');
    expect(body, {'ok': true});
  });

  test('sends no Authorization header while signed out', () async {
    late http.Request seen;
    final api = clientFor((r) async {
      seen = r;
      return http.Response('{}', 200);
    }, idToken: tokens(first: null).provider);
    await api.getJson('/v1/packs');
    expect(seen.headers.containsKey('Authorization'), isFalse);
  });

  test('posts JSON', () async {
    late http.Request seen;
    final api = clientFor((r) async {
      seen = r;
      return http.Response('{}', 200);
    });
    await api.postJson('/v1/sessions', body: {'a': 1});
    expect(seen.method, 'POST');
    expect(seen.headers['Content-Type'], startsWith('application/json'));
    expect(seen.body, '{"a":1}');
  });

  test('a 401 refreshes the token once and retries', () async {
    final t = tokens();
    final auths = <String?>[];
    final api = clientFor((r) async {
      auths.add(r.headers['Authorization']);
      return auths.length == 1
          ? http.Response('{"error":{"code":"token_expired","message":"expired"}}', 401)
          : http.Response('{"ok":true}', 200);
    }, idToken: t.provider);
    expect(await api.getJson('/v1/me'), {'ok': true});
    expect(auths, ['Bearer tok-1', 'Bearer tok-2']);
    expect(t.refreshes, [false, true]);
  });

  test('a second 401 throws UnauthorizedException and does not loop', () async {
    var calls = 0;
    final api = clientFor((r) async {
      calls++;
      return http.Response('{"error":{"code":"invalid_token","message":"no"}}', 401);
    });
    await expectLater(
      api.getJson('/v1/me'),
      throwsA(isA<UnauthorizedException>().having((e) => e.code, 'code', 'invalid_token')),
    );
    expect(calls, 2);
  });

  test('maps the { error } shape onto typed exceptions', () async {
    Future<Object> failWith(int status, [String body = '{"error":{"code":"some_code","message":"msg"}}']) async {
      final api = clientFor((_) async => http.Response(body, status));
      try {
        await api.getJson('/x');
      } catch (e) {
        return e;
      }
      throw StateError('did not throw');
    }

    final forbidden = await failWith(403);
    expect(forbidden, isA<ForbiddenException>().having((e) => e.message, 'message', 'msg'));
    expect(await failWith(404), isA<NotFoundException>());
    expect(await failWith(422), isA<RequestException>().having((e) => e.status, 'status', 422));
    expect(await failWith(500), isA<ServerException>());
  });

  test('429 carries Retry-After', () async {
    final api = clientFor(
      (_) async => http.Response('{"error":{"code":"rate_limited","message":"slow"}}', 429, headers: {'retry-after': '7'}),
    );
    await expectLater(
      api.getJson('/x'),
      throwsA(isA<RateLimitedException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 7))),
    );
  });

  test('an error body that is not our shape still maps by status', () async {
    final api = clientFor((_) async => http.Response('<html>bad gateway</html>', 502));
    await expectLater(
      api.getJson('/x'),
      throwsA(isA<ServerException>().having((e) => e.code, 'code', 'http_502')),
    );
  });

  test('a dropped connection is a NetworkException', () async {
    final api = clientFor((_) async => throw http.ClientException('offline'));
    await expectLater(api.getJson('/x'), throwsA(isA<NetworkException>()));
  });

  test('a token lookup that fails is a NetworkException', () async {
    final api = clientFor(
      (_) async => http.Response('{}', 200),
      idToken: ({bool forceRefresh = false}) async => throw Exception('no network'),
    );
    await expectLater(api.getJson('/x'), throwsA(isA<NetworkException>()));
  });

  test('a 2xx body that is not JSON is a bad_response ServerException', () async {
    final api = clientFor((_) async => http.Response('nope', 200));
    await expectLater(
      api.getJson('/x'),
      throwsA(isA<ServerException>().having((e) => e.code, 'code', 'bad_response')),
    );
  });
}
