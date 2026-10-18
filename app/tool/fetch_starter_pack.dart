// Fetches the current `starter` pack and writes it to app/assets/starter/, so the app ships with
// clips that play before any download. Run from app/:
//
//   dart run tool/fetch_starter_pack.dart --api-base https://api.example.com
//
// Layout it writes (and the app reads, see lib/features/packs/data/starter_pack.dart):
//   assets/starter/manifest.json            the pack manifest, exactly as published
//   assets/starter/clips/{id}-intro.mp3     one file per clip
//   assets/starter/clips/{id}-middle.mp3
//
// Every clip is checked against the manifest's SHA-256 before anything is written, so a failed or
// corrupt download leaves the folder as it was. Commit the result only if it is under 10 MB in
// total; otherwise run this in CI before the build (see docs/ops.md, "Starter clips").
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/features/packs/data/pack_manifest.dart';

/// The most the starter pack may weigh to be committed to the repository.
const starterCommitLimitBytes = 10 * 1024 * 1024;

class StarterFetchException implements Exception {
  const StarterFetchException(this.message);
  final String message;

  @override
  String toString() => 'StarterFetchException: $message';
}

class StarterFetchResult {
  const StarterFetchResult({required this.version, required this.tracks, required this.bytes});
  final int version;
  final int tracks;

  /// Total size of the clips.
  final int bytes;

  bool get fitsInRepository => bytes <= starterCommitLimitBytes;
}

/// Fetches the `starter` pack through `GET {apiBase}/v1/packs` and writes it under [outDir].
/// Throws [StarterFetchException] if there is no starter pack, a download fails, or a clip does
/// not match its checksum; [outDir] is then untouched.
Future<StarterFetchResult> fetchStarterPack({
  required http.Client client,
  required String apiBase,
  required Directory outDir,
  String slug = 'starter',
}) async {
  final base = apiBase.endsWith('/') ? apiBase.substring(0, apiBase.length - 1) : apiBase;
  final list = await _get(client, Uri.parse('$base/v1/packs'));
  final packs = (jsonDecode(utf8.decode(list)) as Map<String, dynamic>)['packs'] as List<dynamic>;
  final listing = packs.cast<Map<String, dynamic>>().where((pack) => pack['slug'] == slug).firstOrNull;
  if (listing == null) {
    throw StarterFetchException('no published pack "$slug" at $base/v1/packs');
  }

  final manifestJson = utf8.decode(await _get(client, Uri.parse(listing['manifestUrl'] as String)));
  final PackManifest manifest;
  try {
    manifest = PackManifest.parse(manifestJson);
  } on PackManifestException catch (e) {
    throw StarterFetchException('the manifest cannot be used: ${e.message}');
  }
  if (manifest.slug != slug) {
    throw StarterFetchException('expected pack "$slug", the manifest is "${manifest.slug}"');
  }

  final files = <String, List<int>>{};
  for (final track in manifest.tracks) {
    for (final (kind, clip) in [('intro', track.intro), ('middle', track.middle)]) {
      final bytes = await _get(client, Uri.parse(clip.url));
      if (sha256.convert(bytes).toString() != clip.sha256) {
        throw StarterFetchException('clip ${track.id} $kind does not match its checksum');
      }
      files['${track.id}-$kind.mp3'] = bytes;
    }
  }

  // Everything verified: replace the folder's contents.
  final clipsDir = Directory(p.join(outDir.path, 'clips'));
  if (await clipsDir.exists()) {
    await for (final entry in clipsDir.list()) {
      if (entry is File && p.extension(entry.path) == '.mp3') await entry.delete();
    }
  }
  await clipsDir.create(recursive: true);
  for (final entry in files.entries) {
    await File(p.join(clipsDir.path, entry.key)).writeAsBytes(entry.value);
  }
  await File(p.join(outDir.path, 'manifest.json')).writeAsString(manifestJson);
  return StarterFetchResult(
    version: manifest.version,
    tracks: manifest.tracks.length,
    bytes: files.values.fold(0, (sum, f) => sum + f.length),
  );
}

Future<List<int>> _get(http.Client client, Uri uri) async {
  final http.Response res;
  try {
    res = await client.get(uri).timeout(const Duration(seconds: 60));
  } catch (e) {
    throw StarterFetchException('could not fetch $uri: $e');
  }
  if (res.statusCode != 200) throw StarterFetchException('$uri answered ${res.statusCode}');
  return res.bodyBytes;
}

Future<void> main(List<String> args) async {
  String? apiBase;
  var out = 'assets/starter';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--api-base' && i + 1 < args.length) apiBase = args[++i];
    if (args[i] == '--out' && i + 1 < args.length) out = args[++i];
  }
  if (apiBase == null || apiBase.isEmpty) {
    stderr.writeln('usage: dart run tool/fetch_starter_pack.dart --api-base <url> [--out assets/starter]');
    exit(64);
  }
  final client = http.Client();
  try {
    final result = await fetchStarterPack(client: client, apiBase: apiBase, outDir: Directory(out));
    final mb = (result.bytes / (1024 * 1024)).toStringAsFixed(1);
    stdout.writeln('starter v${result.version}: ${result.tracks} tracks, $mb MB written to $out');
    stdout.writeln(
      result.fitsInRepository
          ? 'Under 10 MB: commit the files.'
          : 'Over 10 MB: do not commit them. Fetch in CI before the build (docs/ops.md, "Starter clips").',
    );
  } on StarterFetchException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  } finally {
    client.close();
  }
}
