import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_db.dart';
import '../../../core/net/network_kind.dart';
import 'catalog_refresher.dart';
import 'clip_settings.dart';
import 'clip_store.dart';
import 'packs_providers.dart';
import 'starter_pack.dart';

final clipStoreProvider = Provider<ClipStore>((ref) {
  return ClipStore(db: ref.watch(appDbProvider), supportDirectory: () => ref.read(supportDirectoryProvider.future));
});

final clipSettingsProvider = Provider<ClipSettings>((ref) => ClipSettings(ref.watch(appDbProvider)));

final starterPackProvider = Provider<StarterPack>((ref) {
  return StarterPack(
    db: ref.watch(appDbProvider),
    store: ref.watch(clipStoreProvider),
    supportDirectory: () => ref.read(supportDirectoryProvider.future),
  );
});

final catalogRefresherProvider = Provider<CatalogRefresher>((ref) {
  return CatalogRefresher(
    db: ref.watch(appDbProvider),
    api: ref.watch(packsApiProvider),
    store: ref.watch(clipStoreProvider),
  );
});

/// Registers the bundled starter clips. A session waits for this before it reads the catalog, so
/// a first launch is ready to play as soon as the files are copied.
final starterReadyProvider = FutureProvider<void>((ref) async {
  try {
    await ref.watch(starterPackProvider).registerIfChanged();
  } catch (_) {
    // No starter pack must never stop the app.
  }
});

/// What Settings shows as storage used: starter, cached (`stream`) and pack clips.
final storageUsageProvider = StreamProvider<StorageUsage>((ref) => ref.watch(clipStoreProvider).watchUsage());

/// Deletes all `stream` clips. Starter and pack clips stay.
final clearStreamCacheProvider = Provider<Future<void> Function()>((ref) {
  final store = ref.watch(clipStoreProvider);
  return store.clearStreamCache;
});

/// What the phone is connected to now.
final networkKindProvider = Provider<Future<NetworkKind> Function()>((ref) => currentNetworkKind);

/// What the phone is connected to, each time that changes.
final networkChangesProvider = Provider<Stream<NetworkKind> Function()>((ref) => networkKindChanges);

/// Fires whenever the catalog or the clips on the phone change: the starter clips registered, a
/// download finished, a pack installed, the catalog refreshed, the cache trimmed.
final clipsChangedProvider = StreamProvider.autoDispose<void>((ref) {
  final db = ref.watch(appDbProvider);
  return db.tableUpdates(TableUpdateQuery.onAllTables([db.clips, db.catalogTracks])).map((_) {});
});

/// Registers the starter clips, then keeps the catalog fresh: on every start (when online), every
/// 12 hours while the app runs, and again when the app returns to the foreground after that long.
/// The refresh is also what notices a new version of an installed pack (the Settings badge). On
/// start it runs even when the last one is recent: with nothing new it is a single small request.
final catalogStarterProvider = Provider<void>((ref) {
  unawaited(ref.read(starterReadyProvider.future));
  final refresher = ref.watch(catalogRefresherProvider);
  unawaited(refresher.refresh());
  final timer = Timer.periodic(CatalogRefresher.interval, (_) => unawaited(refresher.refresh()));
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(refresher.refreshIfDue()));
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
  });
});
