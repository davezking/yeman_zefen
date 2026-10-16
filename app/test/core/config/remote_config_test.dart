import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yeman_zefen/core/config/remote_config.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/http/api_client.dart';

const _server = {
  'interstitialEveryRounds': 4,
  'registerPromptAfterSessions': 6,
  'registerPromptCooldownDays': 3,
  'minAppVersion': '0.2.0',
  'defaultClipMs': 5000,
};

class _MemoryStore implements RemoteConfigStore {
  _MemoryStore([this.stored]);
  RemoteConfig? stored;
  int writes = 0;

  @override
  Future<RemoteConfig?> read() async => stored;

  @override
  Future<void> write(RemoteConfig config) async {
    writes++;
    stored = config;
  }
}

RemoteConfigService _service({required http.Response Function() answer, required RemoteConfigStore store}) {
  final client = MockClient((request) async {
    expect(request.url.path, '/v1/config');
    return answer();
  });
  final api = ApiClient(baseUrl: 'https://api.test', idToken: ({bool forceRefresh = false}) async => null, client: client);
  return RemoteConfigService(api: api, store: store);
}

http.Response _ok([Map<String, Object> body = _server]) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

void main() {
  group('RemoteConfig.fromJson', () {
    test('reads every field', () {
      final c = RemoteConfig.fromJson(_server);
      expect(c.interstitialEveryRounds, 4);
      expect(c.registerPromptAfterSessions, 6);
      expect(c.registerPromptCooldownDays, 3);
      expect(c.minAppVersion, '0.2.0');
      expect(c.defaultClipMs, 5000);
    });

    test('round-trips through toJson', () {
      expect(RemoteConfig.fromJson(RemoteConfig.defaults.toJson()), RemoteConfig.defaults);
    });

    final bad = <String, Object?>{
      'not an object': 'x',
      'a missing field': Map.of(_server)..remove('interstitialEveryRounds'),
      'a negative count': {..._server, 'registerPromptAfterSessions': -1},
      'a text count': {..._server, 'registerPromptCooldownDays': '3'},
      'a version without patch': {..._server, 'minAppVersion': '1.2'},
      'a clip under a second': {..._server, 'defaultClipMs': 500},
    };
    bad.forEach((name, json) {
      test('refuses $name', () {
        expect(() => RemoteConfig.fromJson(json), throwsFormatException);
      });
    });
  });

  group('isBelowMinimum', () {
    // (installed, minimum, blocked): a build with an unknown version is never blocked.
    const cases = [
      ('0.1.0', '0.1.1', true),
      ('0.1.9', '0.2.0', true),
      ('0.9.9', '1.0.0', true),
      ('0.2.0', '0.2.0', false),
      ('0.2.1', '0.2.0', false),
      ('1.0.0', '0.9.9', false),
      ('dev', '0.2.0', false),
    ];
    for (final (current, minimum, expected) in cases) {
      test('$current against $minimum is ${expected ? 'blocked' : 'allowed'}', () {
        expect(isBelowMinimum(current, minimum), expected);
      });
    }
  });

  group('RemoteConfigService', () {
    test('a fresh install with no network uses the defaults', () async {
      final store = _MemoryStore();
      final service = _service(answer: () => throw StateError('unused'), store: store);
      expect(await service.cached(), RemoteConfig.defaults);
    });

    test('a good answer is used and stored for the next launch', () async {
      final store = _MemoryStore();
      final service = _service(answer: _ok, store: store);
      final fresh = await service.refresh(RemoteConfig.defaults);
      expect(fresh, RemoteConfig.fromJson(_server));
      expect(store.stored, fresh);
    });

    test('offline launch uses the cached value, and a failed fetch keeps it', () async {
      final cached = RemoteConfig.fromJson(_server);
      final store = _MemoryStore(cached);
      final client = MockClient((_) async => throw http.ClientException('no route'));
      final api = ApiClient(baseUrl: 'https://api.test', idToken: ({bool forceRefresh = false}) async => null, client: client);
      final service = RemoteConfigService(api: api, store: store);

      expect(await service.cached(), cached);
      expect(await service.refresh(cached), cached);
      expect(store.writes, 0);
    });

    test('a server error keeps the current config and stores nothing', () async {
      final store = _MemoryStore();
      final service = _service(
        answer: () => http.Response('{"error":{"code":"config_invalid","message":"x"}}', 500),
        store: store,
      );
      expect(await service.refresh(RemoteConfig.defaults), RemoteConfig.defaults);
      expect(store.writes, 0);
    });

    test('an answer the app cannot use does not replace a good cached one', () async {
      final cached = RemoteConfig.fromJson(_server);
      final store = _MemoryStore(cached);
      final service = _service(answer: () => _ok({..._server, 'minAppVersion': 'soon'}), store: store);
      expect(await service.refresh(cached), cached);
      expect(store.stored, cached);
    });
  });

  group('DbRemoteConfigStore', () {
    test('stores, reads back, and treats a corrupt row as nothing stored', () async {
      final db = AppDb(NativeDatabase.memory());
      addTearDown(db.close);
      final store = DbRemoteConfigStore(db);
      expect(await store.read(), isNull);

      await store.write(RemoteConfig.fromJson(_server));
      await store.write(RemoteConfig.fromJson(_server)); // an upsert, not a second row
      expect(await store.read(), RemoteConfig.fromJson(_server));
      expect(await db.select(db.remoteConfigCache).get(), hasLength(1));

      await db.into(db.remoteConfigCache).insertOnConflictUpdate(
        RemoteConfigCacheCompanion.insert(key: 'config', json: '{"oops":true}'),
      );
      expect(await store.read(), isNull);
    });
  });

  group('updateRequiredProvider', () {
    setUp(() => PackageInfo.setMockInitialValues(
      appName: 'yeman_zefen',
      packageName: 'com.yemanzefen.yeman_zefen',
      version: '0.1.5',
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    ));

    ProviderContainer container(String minimum) {
      final c = ProviderContainer(overrides: [
        remoteConfigProvider.overrideWith(() => _FixedConfig(RemoteConfig.defaults.toJsonWith(minAppVersion: minimum))),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('is true when the installed version is below the minimum', () async {
      final c = container('0.2.0');
      await c.read(appVersionProvider.future);
      expect(c.read(updateRequiredProvider), isTrue);
    });

    test('is false when the installed version meets the minimum', () async {
      final c = container('0.1.0');
      await c.read(appVersionProvider.future);
      expect(c.read(updateRequiredProvider), isFalse);
    });
  });
}

class _FixedConfig extends RemoteConfigNotifier {
  _FixedConfig(this._config);
  final RemoteConfig _config;

  @override
  RemoteConfig build() => _config;
}

extension on RemoteConfig {
  RemoteConfig toJsonWith({required String minAppVersion}) => RemoteConfig.fromJson({...toJson(), 'minAppVersion': minAppVersion});
}
