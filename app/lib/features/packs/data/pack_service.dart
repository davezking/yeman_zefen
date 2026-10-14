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
  /// left as it was).
  Future<void> install(PackListing listing) async {
    final json = await api.fetchManifestJson(listing.manifestUrl);
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
    );
  }
}
