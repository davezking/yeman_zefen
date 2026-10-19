import 'pack_installer.dart';
import 'pack_manifest.dart';
import 'packs_api.dart';

/// Lists the published packs and installs one: fetch its manifest, check it,
/// then hand it to the installer.
class PackService {
  PackService({required this.api, required this.installer});

  final PacksApi api;
  final PackInstaller installer;

  Future<List<PackListing>> listPacks() => api.listPacks();

  /// Installs the version [listing] names. Throws if the manifest cannot be
  /// fetched or used, or if the install fails (the installed version is then
  /// left as it was). [isCancelled] is asked once the manifest is in, because
  /// [PackInstaller.cancel] only reaches an install the installer has started.
  /// With [wifiOnly] the clips download only on Wi-Fi.
  Future<void> install(PackListing listing, {bool Function()? isCancelled, bool wifiOnly = false}) async {
    final json = await api.fetchManifestJson(listing.manifestUrl);
    if (isCancelled?.call() ?? false) {
      throw const PackInstallException('cancelled', failure: PackInstallFailure.cancelled);
    }
    final PackManifest manifest;
    try {
      manifest = PackManifest.parse(json);
    } on PackManifestException catch (e) {
      throw PackInstallException('The pack manifest cannot be used: ${e.message}');
    }
    await installer.install(
      manifest,
      json,
      expectedSlug: listing.slug,
      expectedVersion: listing.version,
      wifiOnly: wifiOnly,
    );
  }
}
