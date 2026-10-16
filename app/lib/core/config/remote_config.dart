import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../db/app_db.dart';
import '../http/api_client.dart';
import '../http/api_providers.dart';

final _version = RegExp(r'^\d+\.\d+\.\d+$');

/// The tunables from `GET /v1/config`. [defaults] are what the app uses before the
/// server has ever answered (a fresh install, offline).
@immutable
class RemoteConfig {
  const RemoteConfig({
    required this.interstitialEveryRounds,
    required this.registerPromptAfterSessions,
    required this.registerPromptCooldownDays,
    required this.minAppVersion,
    required this.defaultClipMs,
  });

  static const defaults = RemoteConfig(
    interstitialEveryRounds: 3,
    registerPromptAfterSessions: 5,
    registerPromptCooldownDays: 7,
    minAppVersion: '0.1.0',
    defaultClipMs: 10000,
  );

  /// A round with an interstitial ad after every this many rounds.
  final int interstitialEveryRounds;

  /// Guest players are asked to register after this many completed sessions.
  final int registerPromptAfterSessions;

  /// After a dismissed register prompt, wait this many days before asking again.
  final int registerPromptCooldownDays;

  /// Apps older than this (`major.minor.patch`) must update before they play.
  final String minAppVersion;

  /// Clip length a round uses by default, in ms.
  final int defaultClipMs;

  /// Parses the server's answer. Throws [FormatException] for anything the app cannot use,
  /// so a bad answer never replaces a good cached one.
  factory RemoteConfig.fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw const FormatException('the config is not an object');
    int count(String key) {
      final v = json[key];
      if (v is int && v >= 0) return v;
      throw FormatException('$key is not a whole number');
    }

    final minVersion = json['minAppVersion'];
    if (minVersion is! String || !_version.hasMatch(minVersion)) {
      throw const FormatException('minAppVersion is not major.minor.patch');
    }
    final clip = count('defaultClipMs');
    if (clip < 1000) throw const FormatException('defaultClipMs is under one second');
    return RemoteConfig(
      interstitialEveryRounds: count('interstitialEveryRounds'),
      registerPromptAfterSessions: count('registerPromptAfterSessions'),
      registerPromptCooldownDays: count('registerPromptCooldownDays'),
      minAppVersion: minVersion,
      defaultClipMs: clip,
    );
  }

  Map<String, Object> toJson() => {
    'interstitialEveryRounds': interstitialEveryRounds,
    'registerPromptAfterSessions': registerPromptAfterSessions,
    'registerPromptCooldownDays': registerPromptCooldownDays,
    'minAppVersion': minAppVersion,
    'defaultClipMs': defaultClipMs,
  };

  @override
  bool operator ==(Object other) =>
      other is RemoteConfig &&
      other.interstitialEveryRounds == interstitialEveryRounds &&
      other.registerPromptAfterSessions == registerPromptAfterSessions &&
      other.registerPromptCooldownDays == registerPromptCooldownDays &&
      other.minAppVersion == minAppVersion &&
      other.defaultClipMs == defaultClipMs;

  @override
  int get hashCode => Object.hash(
    interstitialEveryRounds,
    registerPromptAfterSessions,
    registerPromptCooldownDays,
    minAppVersion,
    defaultClipMs,
  );
}

/// True when [current] is older than [minimum]. A [current] that is not `major.minor.patch`
/// (a dev build's version, say) is never blocked.
bool isBelowMinimum(String current, String minimum) {
  if (!_version.hasMatch(current)) return false;
  final a = current.split('.').map(int.parse).toList();
  final b = minimum.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

/// Where the last server answer is kept between launches.
abstract class RemoteConfigStore {
  /// The stored config, or null when none is stored (or what is stored is not usable).
  Future<RemoteConfig?> read();

  Future<void> write(RemoteConfig config);
}

/// Keeps the answer in the `remote_config_cache` table.
class DbRemoteConfigStore implements RemoteConfigStore {
  DbRemoteConfigStore(this.db);

  final AppDb db;
  static const _key = 'config';

  @override
  Future<RemoteConfig?> read() async {
    final row = await (db.select(db.remoteConfigCache)..where((t) => t.key.equals(_key))).getSingleOrNull();
    if (row == null) return null;
    try {
      return RemoteConfig.fromJson(jsonDecode(row.json));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(RemoteConfig config) => db
      .into(db.remoteConfigCache)
      .insertOnConflictUpdate(RemoteConfigCacheCompanion.insert(key: _key, json: jsonEncode(config.toJson())));
}

/// Loads and refreshes the config. Never throws: the answer is always some usable config.
class RemoteConfigService {
  RemoteConfigService({required this.api, required this.store});

  final ApiClient api;
  final RemoteConfigStore store;

  /// The config to start with: the last one the server sent, else [RemoteConfig.defaults].
  Future<RemoteConfig> cached() async => (await store.read()) ?? RemoteConfig.defaults;

  /// Asks the server. On a good answer, stores it and returns it. Offline, a server error or a
  /// bad answer returns [current] and leaves the stored config alone.
  Future<RemoteConfig> refresh(RemoteConfig current) async {
    try {
      final fresh = RemoteConfig.fromJson(await api.getJson('/v1/config'));
      await store.write(fresh);
      return fresh;
    } on ApiException catch (e) {
      developer.log('config not refreshed: $e', name: 'remote_config');
    } on FormatException catch (e) {
      developer.log('config not refreshed: $e', name: 'remote_config');
    }
    return current;
  }
}

final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  return RemoteConfigService(
    api: ref.watch(apiClientProvider),
    store: DbRemoteConfigStore(ref.watch(appDbProvider)),
  );
});

/// The config the app uses right now. Starts at the defaults; [remoteConfigStarterProvider] replaces it.
class RemoteConfigNotifier extends Notifier<RemoteConfig> {
  @override
  RemoteConfig build() => RemoteConfig.defaults;

  void replace(RemoteConfig config) => state = config;
}

final remoteConfigProvider = NotifierProvider<RemoteConfigNotifier, RemoteConfig>(RemoteConfigNotifier.new);

/// The installed app's version (`major.minor.patch`).
final appVersionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// True once the installed version is known and older than the server's minimum: the app shows
/// the update screen instead of its screens.
final updateRequiredProvider = Provider<bool>((ref) {
  final version = ref.watch(appVersionProvider).value;
  if (version == null) return false;
  return isBelowMinimum(version, ref.watch(remoteConfigProvider).minAppVersion);
});

/// Loads the cached config (so an offline launch has the server's values), then asks the server.
/// Read once in main.dart, so it runs on every app start.
final remoteConfigStarterProvider = Provider<void>((ref) {
  final service = ref.watch(remoteConfigServiceProvider);
  final notifier = ref.read(remoteConfigProvider.notifier);
  unawaited(() async {
    try {
      final cached = await service.cached();
      notifier.replace(cached);
      notifier.replace(await service.refresh(cached));
    } catch (e, st) {
      developer.log('config load failed', name: 'remote_config', error: e, stackTrace: st);
    }
  }());
});
