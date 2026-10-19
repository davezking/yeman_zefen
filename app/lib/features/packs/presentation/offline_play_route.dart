import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/net/network_kind.dart';
import '../../../prototype/models.dart' as proto;
import '../../game/application/play_setup.dart';
import '../application/offline_play.dart';
import '../data/clip_providers.dart';
import '../data/packs_providers.dart';
import 'offline_play_screen.dart';

/// Settings › Offline play with the real packs, downloads, settings and storage.
///
/// Every pack state comes from the installer's progress and [packDownloadsProvider], which outlive
/// this screen: a download goes on when the player leaves, and shows its progress on return.
class OfflinePlayRoute extends ConsumerWidget {
  const OfflinePlayRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(currentNetworkProvider).asData?.value;
    // The list failed while offline: fetch it again once the phone is back online.
    ref.listen(currentNetworkProvider, (previous, next) {
      final was = previous?.asData?.value;
      final now = next.asData?.value;
      if (now != null && now != NetworkKind.none && was != now && ref.read(packListingsProvider).hasError) {
        ref.invalidate(packListingsProvider);
      }
    });

    final listingsState = ref.watch(packListingsProvider);
    final listings = listingsState.asData?.value;
    final jobs = ref.watch(packDownloadsProvider);
    final usage = ref.watch(storageUsageProvider).asData?.value;
    final capBytes = ref.watch(streamCacheCapProvider).asData?.value;
    final offline = network == NetworkKind.none;

    final packs = packItems(
      listings: listings,
      installed: ref.watch(installedPacksProvider).asData?.value ?? const [],
      updates: ref.watch(packUpdatesProvider).asData?.value ?? const {},
      jobs: jobs,
      progress: (slug) =>
          jobs[slug]?.running ?? false ? ref.watch(packInstallProgressProvider(slug)).asData?.value : null,
    );
    final downloads = ref.read(packDownloadsProvider.notifier);

    void download(String slug) {
      final listing = listingOf(listings, slug);
      // Offline, or the pack is no longer published: nothing to download it from.
      if (listing == null) return;
      unawaited(downloads.start(listing));
    }

    return OfflinePlayScreen(
      loadingPacks: listingsState.isLoading && !offline,
      wifiOnly: ref.watch(packWifiOnlyProvider).asData?.value ?? true,
      mobilePrefetch: ref.watch(mobilePrefetchProvider).asData?.value ?? true,
      cache: proto.CacheUsage(
        usedMb: megabytes(usage?.streamBytes ?? 0),
        capMb: megabytes(capBytes ?? 0),
        builtInMb: megabytes(usage?.starterBytes ?? 0),
        packsMb: megabytes(usage?.packBytes ?? 0),
      ),
      builtInSongCount: ref.watch(starterSongCountProvider).asData?.value ?? 0,
      packs: packs,
      connection: switch (network) {
        NetworkKind.unmetered => proto.Connection.wifi,
        NetworkKind.none => proto.Connection.offline,
        // Until the connection is known it counts as mobile data, so "Wi-Fi only" still asks.
        NetworkKind.cellular || null => proto.Connection.mobile,
      },
      onBack: () => context.canPop() ? context.pop() : context.go('/settings'),
      onWifiOnly: (on) => unawaited(ref.read(packWifiOnlyProvider.notifier).set(on)),
      onMobilePrefetch: (on) => unawaited(ref.read(mobilePrefetchProvider.notifier).set(on)),
      onClearCache: () => unawaited(ref.read(clearStreamCacheProvider)()),
      onDownload: download,
      onCancel: downloads.cancel,
      onRetry: download,
      onRemove: (slug) => unawaited(downloads.remove(slug)),
    );
  }
}

