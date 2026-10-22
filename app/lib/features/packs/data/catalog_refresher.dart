import 'dart:async';
import 'dart:developer' as developer;


import '../../../core/db/app_db.dart';
import 'clip_store.dart';
import 'pack_manifest.dart';
import 'packs_api.dart';

/// Keeps the local catalog in step with the published packs: lists them through `/v1/packs`,
/// downloads the manifest of each pack that is new or has a newer version, and adds its tracks to
/// `catalog_tracks`. The published manifests together are the catalog, so no other API is needed.
class CatalogRefresher {
  CatalogRefresher({
    required this.db,
    required this.api,
    required this.store,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDb db;
  final PacksApi api;
  final ClipStore store;
  final int Function() _nowMs;

  /// How often the catalog is refreshed while the app runs.
  static const interval = Duration(hours: 12);

  /// How old the last refresh may be when the app comes back to the foreground or back online, so
  /// newly published songs show up without restarting the app.
  static const resumeInterval = Duration(minutes: 15);

  static const refreshedAtKey = 'catalog_refreshed_at';

  /// Where the version of each pack whose manifest is in the catalog is saved. Settings compares it
  /// with the installed version to show that an update is available.
  static const versionKeyPrefix = 'catalog_pack:';
  static String versionKey(String slug) => '$versionKeyPrefix$slug';

  Future<String?> _get(String key) async {
    final row = await (db.select(db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) {
    return db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
  }

  /// The refresh running now, which a second caller joins instead of starting another.
  Future<void>? _running;

  /// When the pack list last came back in this run of the app, even if a pack then failed. A pack
  /// that keeps failing is retried on the same schedule as the rest, not on every resume.
  int? _listedAtMs;

  /// Refreshes if the last successful refresh is older than [olderThan] ([interval] by default),
  /// or there was none. Returns whether a refresh ran. Never throws.
  Future<bool> refreshIfDue({Duration olderThan = interval}) async {
    final saved = int.tryParse(await _get(refreshedAtKey) ?? '');
    final listed = _listedAtMs;
    final last = saved == null ? listed : (listed == null || saved > listed ? saved : listed);
    if (last != null && _nowMs() - last < olderThan.inMilliseconds) return false;
    await refresh();
    return true;
  }

  /// Fetches the pack list, then each manifest that has not been read at its current version. A
  /// pack that fails (offline, a bad manifest) is left for the next refresh. The refresh time is
  /// saved only when the list itself came back, so an offline start tries again soon. A call while
  /// a refresh runs waits for that one.
  Future<void> refresh() => _running ??= _refresh().whenComplete(() => _running = null);

  Future<void> _refresh() async {
    final List<PackListing> listings;
    try {
      listings = await api.listPacks();
    } catch (e) {
      developer.log('catalog refresh: pack list failed', name: 'catalog', error: e);
      return;
    }
    _listedAtMs = _nowMs();
    var allOk = true;
    for (final listing in listings) {
      final known = int.tryParse(await _get(versionKey(listing.slug)) ?? '');
      if (known != null && known >= listing.version) continue;
      try {
        final json = await api.fetchManifestJson(listing.manifestUrl);
        final manifest = PackManifest.parse(json);
        if (manifest.slug != listing.slug || manifest.version != listing.version) {
          throw PackManifestException('manifest is ${manifest.slug} v${manifest.version}');
        }
        await db.transaction(() async {
          await store.upsertCatalog(manifest.tracks);
          await _set(versionKey(listing.slug), '${manifest.version}');
        });
      } catch (e) {
        allOk = false;
        developer.log('catalog refresh: ${listing.slug} failed', name: 'catalog', error: e);
      }
    }
    if (allOk) await _set(refreshedAtKey, '${_nowMs()}');
  }
}
