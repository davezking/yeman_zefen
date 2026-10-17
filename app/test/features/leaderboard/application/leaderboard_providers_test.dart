import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
import 'package:yeman_zefen/core/http/api_providers.dart';
import 'package:yeman_zefen/features/leaderboard/application/leaderboard_providers.dart';
import 'package:yeman_zefen/prototype/models.dart';

Future<String?> _token({bool forceRefresh = false}) async => 'token';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _registered = AuthState(uid: 'user', isAnonymous: false, providers: ['google.com']);
const _guest = AuthState(uid: 'guest');

/// The board for [auth], with the server answering through [handler]. Returns the paths asked for.
Future<(LeaderboardView, List<String>)> _board(AuthState auth, http.Response Function(String path) handler) async {
  final asked = <String>[];
  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith((ref) => Stream.value(auth)),
      apiClientProvider.overrideWithValue(
        ApiClient(
          baseUrl: 'https://api.test',
          idToken: _token,
          client: MockClient((req) async {
            asked.add(req.url.path);
            return handler(req.url.path);
          }),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(authStateProvider, (_, _) {});
  await container.read(authStateProvider.future);
  container.listen(leaderboardProvider, (_, _) {});
  final view = await container.read(leaderboardProvider.future);
  return (view, asked);
}

final _top = {
  'entries': [
    {'rank': 1, 'displayName': 'Selam', 'points': 900},
    {'rank': 2, 'displayName': 'Abebe', 'points': 400},
  ],
};

void main() {
  test('a registered player sees the board, their own row and their name', () async {
    final (view, _) = await _board(_registered, (path) {
      return switch (path) {
        '/v1/leaderboard' => _json(_top),
        '/v1/leaderboard/me' => _json({
          'me': {'points': 120, 'rank': 7},
        }),
        _ => _json({'displayName': 'Dawit'}),
      };
    });

    expect(view.state, LeaderboardState.ready);
    expect(view.entries, hasLength(2));
    expect((view.me?.rank, view.me?.name, view.me?.points), (7, 'Dawit', 120));
    expect(view.user.displayName, 'Dawit');
    expect(view.user.weeklyRank, 7);
  });

  test('when only the own row fails, the board still shows and the player stays registered', () async {
    final (view, _) = await _board(_registered, (path) {
      return switch (path) {
        '/v1/leaderboard' => _json(_top),
        '/v1/leaderboard/me' => _json({
          'error': {'code': 'internal', 'message': 'boom'},
        }, 500),
        _ => _json({'displayName': 'Dawit'}),
      };
    });

    expect(view.state, LeaderboardState.ready);
    expect(view.entries, hasLength(2));
    expect(view.me, isNull);
    expect(view.user.isGuest, isFalse);
  });

  test('an answer the app cannot read shows the offline state, not an endless skeleton', () async {
    final (view, _) = await _board(_registered, (path) {
      return switch (path) {
        '/v1/leaderboard' => _json({'entries': 'nope'}),
        '/v1/leaderboard/me' => _json({'me': null}),
        _ => _json({'displayName': 'Dawit'}),
      };
    });

    expect(view.state, LeaderboardState.offlineNone);
    expect(view.user.isGuest, isFalse);
  });

  test('a failed board request shows the offline state', () async {
    final (view, _) = await _board(_guest, (path) {
      return _json({
        'error': {'code': 'internal', 'message': 'boom'},
      }, 500);
    });

    expect(view.state, LeaderboardState.offlineNone);
  });

  test('a guest reads only the board: no own row, no profile', () async {
    final (view, asked) = await _board(_guest, (path) => _json(_top));

    expect(asked, ['/v1/leaderboard']);
    expect(view.user.isGuest, isTrue);
    expect(view.me, isNull);
  });

  test('an empty board is the empty state', () async {
    final (view, _) = await _board(_guest, (path) => _json({'entries': <Object?>[]}));

    expect(view.state, LeaderboardState.empty);
  });
}
