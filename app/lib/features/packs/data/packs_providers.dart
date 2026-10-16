import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/db/app_db.dart';
import '../../../core/http/api_providers.dart';
import '../domain/pack_install_progress.dart';
import 'clip_downloader.dart';
import 'pack_installer.dart';
import 'pack_service.dart';
import 'packs_api.dart';

final packsApiProvider = Provider<PacksApi>((ref) {
  final api = PacksApi(api: ref.watch(apiClientProvider));
  // The shared ApiClient is closed by its own provider; only the CDN client is ours.
  ref.onDispose(api.closeCdn);
  return api;
});

final clipDownloaderProvider = Provider<ClipDownloader>((ref) => BackgroundClipDownloader());

/// Where pack files live. Paths in `local_tracks` are relative to this directory.
final supportDirectoryProvider = FutureProvider<Directory>((ref) => getApplicationSupportDirectory());

final packInstallerProvider = Provider<PackInstaller>((ref) {
  final installer = PackInstaller(
    db: ref.watch(appDbProvider),
    downloader: ref.watch(clipDownloaderProvider),
    supportDirectory: getApplicationSupportDirectory,
  );
  ref.onDispose(installer.dispose);
  return installer;
});

/// Live progress for one pack, keyed by slug.
final packInstallProgressProvider =
    StreamProvider.family<PackInstallProgress, String>((ref, slug) {
  return ref.watch(packInstallerProvider).progressFor(slug);
});

final packServiceProvider = Provider<PackService>((ref) {
  return PackService(api: ref.watch(packsApiProvider), installer: ref.watch(packInstallerProvider));
});

/// The packs the API lists. Re-fetched each time the packs screen opens.
///
/// No automatic retry: Riverpod would retry a failure up to 10 times over
/// about 40 s, and an offline phone would show a spinner the whole time. The
/// screen has a Try again button instead.
final packListingsProvider = FutureProvider.autoDispose<List<PackListing>>(
  (ref) => ref.watch(packServiceProvider).listPacks(),
  retry: (_, _) => null,
);

/// Installed pack versions by slug, updated as installs finish.
final installedVersionsProvider = StreamProvider<Map<String, int>>((ref) {
  final db = ref.watch(appDbProvider);
  return db.select(db.installedPacks).watch().map((rows) => {for (final r in rows) r.slug: r.version});
});
