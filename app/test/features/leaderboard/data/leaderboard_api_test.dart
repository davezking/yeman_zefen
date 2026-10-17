import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
import 'package:yeman_zefen/features/leaderboard/data/leaderboard_api.dart';
import 'package:yeman_zefen/prototype/models.dart';

Future<String?> _token({bool forceRefresh = false}) async => 'token';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  group('periodFor', () {
    test('maps the scopes to the API periods', () {
      expect(LeaderboardApi.periodFor(LeaderboardScope.weekly), 'week');
      expect(LeaderboardApi.periodFor(LeaderboardScope.allTime), 'all');
    });
  });

  group('parseEntries', () {
    test('keeps the server rank, name and points, in order', () {
      final entries = parseEntries({
        'entries': [
          {'rank': 1, 'displayName': 'Selam', 'country': 'ET', 'points': 900},
          {'rank': 1, 'displayName': null, 'country': null, 'points': 900},
          {'rank': 3, 'displayName': 'Abebe', 'country': 'ET', 'points': 400},
        ],
      });

      expect(entries.map((e) => (e.rank, e.name, e.points)).toList(), [
        (1, 'Selam', 900),
        (1, '', 900),
        (3, 'Abebe', 400),
      ]);
    });

    test('an empty board is an empty list', () {
      expect(parseEntries({'entries': <Object?>[]}), isEmpty);
    });

    test('a malformed answer is a FormatException, not a half-built board', () {
      expect(() => parseEntries({'entries': 'nope'}), throwsFormatException);
      expect(
        () => parseEntries({
          'entries': [
            {'rank': 'one', 'points': 1},
          ],
        }),
        throwsFormatException,
      );
      expect(() => parseEntries(['not', 'an', 'object']), throwsFormatException);
    });
  });

  group('parseMe', () {
    test('a ranked player gets their own row, under their own name', () {
      final me = parseMe({
        'me': {'points': 250, 'rank': 4},
      }, displayName: 'Selam');

      expect((me?.rank, me?.name, me?.points), (4, 'Selam', 250));
    });

    test('a player who is not ranked this period has no row', () {
      expect(parseMe({'me': null}, displayName: 'Selam'), isNull);
    });
  });

  group('LeaderboardApi', () {
    test('asks for the period and era, and parses the rows', () async {
      Uri? asked;
      final client = ApiClient(
        baseUrl: 'https://api.test',
        idToken: _token,
        client: MockClient((req) async {
          asked = req.url;
          return _json({
            'entries': [
              {'rank': 1, 'displayName': 'Selam', 'points': 10},
            ],
          });
        }),
      );

      final entries = await LeaderboardApi(client).top(LeaderboardScope.allTime, 2);

      expect(asked?.path, '/v1/leaderboard');
      expect(asked?.queryParameters, {'period': 'all', 'generation': '2'});
      expect(entries.single.name, 'Selam');
    });

    test('a failed request is an ApiException the caller can show as offline', () async {
      final client = ApiClient(
        baseUrl: 'https://api.test',
        idToken: _token,
        client: MockClient((req) async => http.Response('{"error":{"code":"boom","message":"no"}}', 500)),
      );

      expect(LeaderboardApi(client).top(LeaderboardScope.weekly, 0), throwsA(isA<ApiException>()));
    });
  });
}
