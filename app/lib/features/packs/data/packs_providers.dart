import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/app_db.dart';
import '../domain/pack_install_progress.dart';
import 'clip_downloader.dart';
import 'pack_installer.dart';
import 'packs_api.dart';

final packsApiProvider = Provider<PacksApi>((ref) {
  final api = PacksApi(baseUrl: AppConfig.apiBase);
  ref.onDispose(api.close);
  return api;
});

final clipDownloaderProvider = Provider<ClipDownloader>((ref) => BackgroundClipDownloader());

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
