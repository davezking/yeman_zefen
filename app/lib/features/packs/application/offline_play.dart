import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_db.dart';
import '../../../prototype/models.dart' as proto;
import '../data/catalog_refresher.dart';
import '../data/clip_providers.dart';
import '../data/clip_settings.dart';
import '../data/pack_installer.dart';
import '../data/packs_api.dart';
import '../data/packs_providers.dart';
import '../data/starter_pack.dart';
import '../domain/pack_install_progress.dart';
import '../domain/pack_update.dart';
import '../../settings/application/settings_providers.dart';

/// Whole megabytes, rounded up so a small pack or cache never shows 0 MB.
int megabytes(int bytes) => (bytes + 1024 * 1024 - 1) ~/ (1024 * 1024);

/// A pack download the player started, from the tap until it is installed, cancelled or failed.
class PackJob {
  const PackJob.running({this.retryingCorrupt = false})
      : running = true,
        problem = null,
        missingBytes = null;

  const PackJob.failed(proto.PackProblem this.problem, {this.missingBytes})
      : running = false,
        retryingCorrupt = false;

  final bool running;

  /// A file failed its checksum on every try, and the download is running again by itself.
  final bool retryingCorrupt;
  final proto.PackProblem? problem;

  /// For [proto.PackProblem.storageFull]: what the download still needed.
  final int? missingBytes;
}

/// The pack downloads the player started. It lives as long as the app, so a download goes on when
/// the player leaves Offline play, and its state is still there when they come back.
class PackDownloadsNotifier extends Notifier<Map<String, PackJob>> {
  /// The current run of each pack. A run that is no longer current (cancelled, or followed by a
  /// new one) changes nothing when it ends, and stops before the installer starts if it can.
  final _current = <String, Object>{};

  @override
  Map<String, PackJob> build() => const {};

  void _put(String slug, PackJob? job) {
    if (!ref.mounted) return;
    final next = {...state};
    if (job == null) {
      next.remove(slug);
    } else {
      next[slug] = job;
    }
    state = next;
  }

  /// Downloads or updates the pack [slug], unless it is already downloading. Its listing comes
  /// from [listings]; when they lack it (the list failed to load, or is stale) the list is fetched
  /// again, and the pack fails with "Download failed" if it is still missing.
  ///
  /// With [wifiOnly] the clips download only on Wi-Fi, also if the phone moves to mobile data
  /// meanwhile. A file that fails its checksum on every try gets one more whole run by itself,
  /// with the same rule, before the player is asked.
  Future<void> start(String slug, {List<PackListing>? listings, bool wifiOnly = false}) async {
    if (state[slug]?.running ?? false) return;
    final run = Object();
    _current[slug] = run;
    _put(slug, const PackJob.running());
    var listing = listingOf(listings, slug);
    if (listing == null) {
      // A list still loading is waited for; one that failed or lacks the pack is fetched again.
      if (!ref.read(packListingsProvider).isLoading) ref.invalidate(packListingsProvider);
      // Listened to while it loads: an unlistened provider would be paused or disposed.
      final list = ref.listen(packListingsProvider.future, (_, _) {});
      try {
        listing = listingOf(await list.read(), slug);
      } catch (e) {
        developer.log('pack list failed', name: 'packs', error: e);
      } finally {
        list.close();
      }
      if (!identical(_current[slug], run)) return;
      if (listing == null) {
        _current.remove(slug);
        _put(slug, const PackJob.failed(proto.PackProblem.downloadFailed));
        return;
      }
    }
    await _run(listing, run, wifiOnly: wifiOnly, retryingCorrupt: false);
  }

  Future<void> _run(
    PackListing listing,
    Object run, {
    required bool wifiOnly,
    required bool retryingCorrupt,
  }) async {
    final slug = listing.slug;
    bool current() => identical(_current[slug], run);
    _put(slug, PackJob.running(retryingCorrupt: retryingCorrupt));
    PackJob? outcome;
    try {
      await ref.read(packServiceProvider).install(listing, isCancelled: () => !current(), wifiOnly: wifiOnly);
    } on PackInstallException catch (e) {
      switch (e.failure) {
        case PackInstallFailure.cancelled:
          break;
        case PackInstallFailure.checksum when !retryingCorrupt && current():
          return _run(listing, run, wifiOnly: wifiOnly, retryingCorrupt: true);
        case PackInstallFailure.storageFull:
          outcome = PackJob.failed(proto.PackProblem.storageFull, missingBytes: e.missingBytes);
        case _:
          developer.log('pack install failed', name: 'packs', error: e);
          outcome = const PackJob.failed(proto.PackProblem.downloadFailed);
      }
    } catch (e, st) {
      // Offline, or the manifest could not be fetched. The reason goes to the log.
      developer.log('pack install failed', name: 'packs', error: e, stackTrace: st);
      outcome = const PackJob.failed(proto.PackProblem.downloadFailed);
    }
    // A cancelled or replaced run leaves the pack's state to whatever came after it.
    if (!current()) return;
    _current.remove(slug);
    _put(slug, outcome);
  }

  /// Stops a download, including the files under way. Files that verified stay, so downloading
  /// again continues from there; an update that is cancelled leaves the installed version.
  void cancel(String slug) {
    _current.remove(slug);
    ref.read(packInstallerProvider).cancel(slug);
    _put(slug, null);
  }

  /// Removes an installed pack. Its clips join the stream cache, which is then trimmed to its cap.
  /// During a game this waits for the game to end.
  Future<void> remove(String slug) async {
    try {
      await ref.read(packInstallerProvider).remove(slug);
      final cap = await ref.read(clipSettingsProvider).streamCacheCapBytes();
      await ref.read(clipStoreProvider).evict(cap);
    } catch (e, st) {
      developer.log('pack removal failed', name: 'packs', error: e, stackTrace: st);
    }
  }
}

final packDownloadsProvider = NotifierProvider<PackDownloadsNotifier, Map<String, PackJob>>(
  PackDownloadsNotifier.new,
);

/// An installed pack, as its manifest describes it.
class InstalledPackInfo {
  const InstalledPackInfo({
    required this.slug,
    required this.version,
    required this.nameAm,
    required this.nameEn,
    required this.songCount,
    required this.totalBytes,
    this.generationId,
  });

  final String slug;
  final int version;
  final String nameAm;
  final String nameEn;
  final int songCount;
  final int totalBytes;
  final int? generationId;

  /// Reads what the screen needs from the stored manifest. A manifest that cannot be read still
  /// lists the pack, under its slug, so it can be removed.
  factory InstalledPackInfo.of(InstalledPack row) {
    var nameAm = row.slug;
    var nameEn = row.slug;
    var songs = 0;
    int? generationId;
    try {
      final json = jsonDecode(row.manifestJson) as Map<String, dynamic>;
      final names = json['names'] as Map<String, dynamic>;
      nameAm = names['am'] as String;
      nameEn = names['en'] as String;
      songs = (json['tracks'] as List<dynamic>).length;
      generationId = json['generationId'] as int?;
    } catch (_) {}
    return InstalledPackInfo(
      slug: row.slug,
      version: row.version,
      nameAm: nameAm,
      nameEn: nameEn,
      songCount: songs,
      totalBytes: row.totalBytes,
      generationId: generationId,
    );
  }
}

final installedPacksProvider = StreamProvider<List<InstalledPackInfo>>((ref) {
  final db = ref.watch(appDbProvider);
  return db.select(db.installedPacks).watch().map((rows) => [for (final r in rows) InstalledPackInfo.of(r)]);
});

/// Installed packs with a newer version in the catalog. The catalog refresher reads the pack list
/// on start, every 12 hours and when the app comes back after that long, so this follows what the
/// admin site publishes, and it still holds offline.
final packUpdatesProvider = StreamProvider<Set<String>>((ref) {
  final db = ref.watch(appDbProvider);
  return db
      .customSelect(
        'SELECT p.slug AS slug FROM installed_packs p '
        'JOIN app_settings s ON s.key = ? || p.slug '
        'WHERE CAST(s.value AS INTEGER) > p.version',
        variables: [Variable.withString(CatalogRefresher.versionKeyPrefix)],
        readsFrom: {db.installedPacks, db.appSettings},
      )
      .watch()
      .map((rows) => {for (final r in rows) r.read<String>('slug')});
});

/// An installed pack has an update: the badge on the Settings tab and on Offline play.
final packUpdateAvailableProvider = Provider<bool>((ref) {
  return ref.watch(packUpdatesProvider).asData?.value.isNotEmpty ?? false;
});

/// How many songs came with the app.
final starterSongCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(appDbProvider);
  return (db.select(db.clips)..where((c) => c.source.equals(ClipSource.starter)))
      .watch()
      .map((rows) => {for (final r in rows) r.trackId}.length);
});

/// The cap of the stream cache, in bytes.
final streamCacheCapProvider = FutureProvider<int>((ref) => ref.watch(clipSettingsProvider).streamCacheCapBytes());

/// "Download packs on Wi-Fi only", on by default. Saved where [ClipSettings] reads it.
class PackWifiOnlyNotifier extends FlagSettingNotifier {
  @override
  String get key => ClipSettings.packWifiOnlyKey;
  @override
  bool get fallback => true;
}

/// "Download upcoming songs on mobile data", on by default. Saved where [ClipSettings] reads it,
/// which is what the prefetcher goes by.
class MobilePrefetchNotifier extends FlagSettingNotifier {
  @override
  String get key => ClipSettings.prefetchOnMobileKey;
  @override
  bool get fallback => true;
}

final packWifiOnlyProvider = NotifierProvider<PackWifiOnlyNotifier, bool>(PackWifiOnlyNotifier.new);

final mobilePrefetchProvider = NotifierProvider<MobilePrefetchNotifier, bool>(MobilePrefetchNotifier.new);

/// The pack rows of Offline play: the installed packs, then the listed packs that are not
/// installed (the starter pack is built in and never listed).
///
/// [listings] is null while the list loads or when it cannot be fetched; the installed packs still
/// show then. [progress] is the installer's latest progress for a pack.
List<proto.PackItem> packItems({
  required List<PackListing>? listings,
  required List<InstalledPackInfo> installed,
  required Set<String> updates,
  required Map<String, PackJob> jobs,
  required PackInstallProgress? Function(String slug) progress,
}) {
  final listed = {
    for (final l in listings ?? const <PackListing>[])
      if (l.slug != starterPackSlug) l.slug: l,
  };
  final installedSlugs = {for (final p in installed) p.slug};

  proto.PackItem item({
    required String slug,
    required String nameAm,
    required String nameEn,
    required int? generationId,
    required int songCount,
    required int bytes,
    required int? installedVersion,
  }) {
    final listing = listed[slug];
    final hasUpdate = listing == null
        ? updates.contains(slug)
        : isUpdateAvailable(installedVersion: installedVersion, listedVersion: listing.version);
    final base = proto.PackItem(
      id: slug,
      nameAm: nameAm,
      nameEn: nameEn,
      generationId: generationId ?? 0,
      songCount: songCount,
      sizeMb: megabytes(bytes),
      updateSizeMb: hasUpdate && listing != null ? megabytes(listing.totalBytes) : null,
      status: installedVersion == null
          ? proto.PackStatus.notInstalled
          : hasUpdate
              ? proto.PackStatus.updateAvailable
              : proto.PackStatus.installed,
    );
    final job = jobs[slug];
    if (job == null) return base;
    final updating = installedVersion != null;
    if (!job.running) {
      return base.copyWith(
        status: proto.PackStatus.failed,
        updating: updating,
        problem: job.problem,
        shortfallMb: job.missingBytes == null ? null : megabytes(job.missingBytes!),
      );
    }
    if (job.retryingCorrupt) {
      return base.copyWith(status: proto.PackStatus.failed, updating: updating, problem: proto.PackProblem.corrupt);
    }
    final p = progress(slug);
    // Before the installer has this run (fetching the manifest), its last progress is the end of
    // an earlier run, which says nothing about this one.
    final live = p != null && !p.isTerminal;
    if (live && p.bytesTotal > 0 && p.bytesDone >= p.bytesTotal) {
      return base.copyWith(status: proto.PackStatus.verifying, updating: updating, clearProgress: true);
    }
    return base.copyWith(
      status: proto.PackStatus.downloading,
      updating: updating,
      progress: live && p.bytesTotal > 0 ? p.bytesDone / p.bytesTotal : null,
      clearProgress: !live || p.bytesTotal == 0,
    );
  }

  return [
    for (final p in installed)
      item(
        slug: p.slug,
        nameAm: p.nameAm,
        nameEn: p.nameEn,
        generationId: listed[p.slug]?.generationId ?? p.generationId,
        songCount: p.songCount,
        bytes: p.totalBytes,
        installedVersion: p.version,
      ),
    for (final l in listed.values)
      if (!installedSlugs.contains(l.slug))
        item(
          slug: l.slug,
          nameAm: l.nameAm,
          nameEn: l.nameEn,
          generationId: l.generationId,
          songCount: l.trackCount,
          bytes: l.totalBytes,
          installedVersion: null,
        ),
  ];
}

/// The listing of [slug], to download it, or null when the list does not have it.
PackListing? listingOf(List<PackListing>? listings, String slug) {
  for (final l in listings ?? const <PackListing>[]) {
    if (l.slug == slug) return l;
  }
  return null;
}
