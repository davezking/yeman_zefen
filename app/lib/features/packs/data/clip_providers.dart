import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/db/app_db.dart';
import '../../../core/http/api_providers.dart';
import '../../../core/net/network_kind.dart';
import 'catalog_refresher.dart';
import 'clip_checker.dart';
import 'clip_reporter.dart';
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

final clipReporterProvider = Provider<ClipReporter>((ref) {
  return ClipReporter(db: ref.watch(appDbProvider), store: ref.watch(clipStoreProvider), api: ref.watch(apiClientProvider));
});

final clipCheckerProvider = Provider<ClipChecker>((ref) {
  final settings = ref.watch(clipSettingsProvider);
  final network = ref.watch(networkKindProvider);
  return ClipChecker(
    db: ref.watch(appDbProvider),
    store: ref.watch(clipStoreProvider),
    installer: ref.watch(packInstallerProvider),
    starter: ref.watch(starterPackProvider),
    // Repairs follow the same rule as prefetching while playing.
    allowDownloads: () async => switch (await network()) {
      NetworkKind.unmetered => true,
      NetworkKind.cellular => await settings.prefetchOnMobile(),
      NetworkKind.none => false,
    },
  );
});

/// Checks the clip files on the phone once the starter clips are registered, and sends clip
/// reports left over from earlier: on start, once the player has a uid, and when back online.
final clipHealthStarterProvider = Provider<void>((ref) {
  final checker = ref.watch(clipCheckerProvider);
  unawaited(ref.read(starterReadyProvider.future).then((_) => checker.run()));
  final reporter = ref.watch(clipReporterProvider);
  ref.listen<AsyncValue<AuthState>>(authStateProvider, (_, next) {
    if (next.value?.hasUid ?? false) unawaited(reporter.flush());
  }, fireImmediately: true);
  final online = connectivityOnlineChanges().listen((online) {
    if (online) unawaited(reporter.flush());
  }, onError: (Object _) {});
  ref.onDispose(() => unawaited(online.cancel()));
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
/// 12 hours while the app runs, and when the app returns to the foreground or comes back online
/// with the last refresh more than 15 minutes old (an offline start is caught up as soon as the
/// phone connects). The refresh is also what notices a new version of an installed pack (the
/// Settings badge). On start it runs even when the last one is recent: with nothing new it is a
/// single small request.
final catalogStarterProvider = Provider<void>((ref) {
  unawaited(ref.read(starterReadyProvider.future));
  final refresher = ref.watch(catalogRefresherProvider);
  unawaited(refresher.refresh());
  void catchUp() => unawaited(refresher.refreshIfDue(olderThan: CatalogRefresher.resumeInterval));
  final timer = Timer.periodic(CatalogRefresher.interval, (_) => unawaited(refresher.refresh()));
  final lifecycle = AppLifecycleListener(onResume: catchUp);
  final online = connectivityOnlineChanges().listen((online) {
    if (online) catchUp();
  }, onError: (Object _) {});
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
    unawaited(online.cancel());
  });
});
