
import '../../../core/db/app_db.dart';
import 'clip_store.dart';

/// The choices that steer clip delivery, saved in `app_settings`. Settings → Offline play edits
/// them; the prefetcher, the cache and pack downloads read them.
class ClipSettings {
  ClipSettings(this.db);

  final AppDb db;

  static const prefetchOnMobileKey = 'prefetch_on_mobile';
  static const streamCacheCapMbKey = 'stream_cache_cap_mb';
  static const packWifiOnlyKey = 'pack_wifi_only';

  Future<String?> _get(String key) async {
    final row = await (db.select(db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) {
    return db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
  }

  /// "Download upcoming songs on mobile data". On unless the player turned it off.
  Future<bool> prefetchOnMobile() async => (await _get(prefetchOnMobileKey)) != '0';

  Future<void> setPrefetchOnMobile(bool on) => _set(prefetchOnMobileKey, on ? '1' : '0');

  /// "Download packs on Wi-Fi only". On unless the player turned it off.
  Future<bool> packWifiOnly() async => (await _get(packWifiOnlyKey)) != '0';

  Future<void> setPackWifiOnly(bool on) => _set(packWifiOnlyKey, on ? '1' : '0');

  /// The cap for prefetched clips, in bytes.
  Future<int> streamCacheCapBytes() async {
    final mb = int.tryParse(await _get(streamCacheCapMbKey) ?? '');
    return mb == null || mb < 0 ? ClipStore.defaultStreamCacheCapBytes : mb * 1024 * 1024;
  }

  Future<void> setStreamCacheCapMb(int mb) => _set(streamCacheCapMbKey, '$mb');
}
