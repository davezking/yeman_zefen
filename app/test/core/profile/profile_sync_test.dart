import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
import 'package:yeman_zefen/core/profile/profile_sync.dart';

class MemoryStore implements ProfileSyncStore {
  final values = <String, int>{};

  @override
  Future<int?> lastSyncedAt(String key) async => values[key];

  @override
  Future<void> markSynced(String key, int atMs) async => values[key] = atMs;
}

void main() {
  late MemoryStore store;
  late List<http.Request> requests;
  late int status;
  late DateTime now;
  late ProfileSync sync;

  setUp(() {
    store = MemoryStore();
    requests = [];
    status = 200;
    now = DateTime.utc(2026, 10, 16, 12);
    final client = ApiClient(
      baseUrl: 'https://api.test',
      idToken: ({bool forceRefresh = false}) async => 'token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          status == 200 ? jsonEncode({'id': 'u1'}) : jsonEncode({'error': {'code': 'internal', 'message': 'x'}}),
          status,
        );
      }),
    );
    sync = ProfileSync(api: client, store: store, now: () => now);
  });

  const guest = AuthState(uid: 'u1');

  test('sends PUT /v1/me with no identity fields', () async {
    expect(await sync.syncIfDue(guest), isTrue);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/v1/me');
    expect(requests.single.headers['Authorization'], 'Bearer token');
    expect(jsonDecode(requests.single.body), <String, Object?>{});
  });

  test('does nothing without a uid', () async {
    expect(await sync.syncIfDue(AuthState.signedOut), isFalse);
    expect(requests, isEmpty);
  });

  test('skips a second sync inside six hours, allows it after', () async {
    expect(await sync.syncIfDue(guest), isTrue);
    now = now.add(const Duration(hours: 5, minutes: 59));
    expect(await sync.syncIfDue(guest), isFalse);
    expect(requests, hasLength(1));
    now = now.add(const Duration(minutes: 2));
    expect(await sync.syncIfDue(guest), isTrue);
    expect(requests, hasLength(2));
  });

  test('a different account, or a guest who just registered, syncs at once', () async {
    await sync.syncIfDue(guest);
    expect(await sync.syncIfDue(const AuthState(uid: 'u2')), isTrue);
    expect(await sync.syncIfDue(const AuthState(uid: 'u1', isAnonymous: false, providers: ['google.com'])), isTrue);
    expect(requests, hasLength(3));
  });

  test('a failed call is not recorded and is retried on the next trigger', () async {
    status = 500;
    expect(await sync.syncIfDue(guest), isFalse);
    expect(store.values, isEmpty);
    status = 200;
    expect(await sync.syncIfDue(guest), isTrue);
    expect(requests, hasLength(2));
  });

  test('a clock set back does not block syncing', () async {
    await sync.syncIfDue(guest);
    now = now.subtract(const Duration(days: 2));
    expect(await sync.syncIfDue(guest), isTrue);
  });

  test('overlapping calls send one request', () async {
    final results = await Future.wait([sync.syncIfDue(guest), sync.syncIfDue(guest)]);
    expect(results.where((r) => r), hasLength(1));
    expect(requests, hasLength(1));
  });
}
