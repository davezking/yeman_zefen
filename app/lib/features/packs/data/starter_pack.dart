import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/db/app_db.dart';
import 'checksum.dart';
import 'clip_store.dart';
import 'pack_manifest.dart';

/// Where the bundled starter pack lives in the app's assets. `app/tool/fetch_starter_pack.dart`
/// writes it: `manifest.json`, then each clip as `clips/{trackId}-{intro|middle}.mp3`.
const starterAssetDir = 'assets/starter';

/// The slug of the pack the starter clips come from. It is built into the app, so Settings →
/// Offline play does not list it.
const starterPackSlug = 'starter';

/// Puts the bundled starter clips on the device and into the catalog, so the first round of a
/// first launch needs no network.
///
/// `just_audio` is handed file paths by the clip player, so each clip is copied once from the
/// asset bundle to `starter/` in the support directory and checked against the manifest's
/// SHA-256 on the way. The copy happens on the first start and again after an app update that
/// changes the starter manifest (its pack version or publish time).
class StarterPack {
  StarterPack({
    required this.db,
    required this.store,
    required this.supportDirectory,
    AssetBundle? bundle,
  }) : _bundle = bundle ?? rootBundle;

  final AppDb db;
  final ClipStore store;
  final Future<Directory> Function() supportDirectory;
  final AssetBundle _bundle;

  static const markerKey = 'starter_manifest';

  /// Registers the starter tracks if the bundled manifest is new. Returns how many tracks it
  /// registered; 0 when there is no bundled starter pack, it is already registered, or nothing
  /// in it verified. Never throws: a broken or missing starter pack must not stop the app.
  Future<int> registerIfChanged() async {
    final String json;
    try {
      json = await _bundle.loadString('$starterAssetDir/manifest.json');
    } catch (_) {
      return 0; // This build has no starter pack.
    }
    final PackManifest manifest;
    try {
      manifest = PackManifest.parse(json);
    } on PackManifestException {
      return 0;
    }
    final marker = '${manifest.slug}:${manifest.version}:${manifest.publishedAt}';
    final saved = await (db.select(db.appSettings)..where((t) => t.key.equals(markerKey))).getSingleOrNull();
    if (saved?.value == marker && await _allRegistered(manifest)) return 0;

    final base = await supportDirectory();
    final verified = <ManifestTrack>[];
    for (final track in manifest.tracks) {
      try {
        await _copy(base, track.id, ClipKind.intro, track.intro);
        await _copy(base, track.id, ClipKind.middle, track.middle);
        verified.add(track);
      } catch (_) {
        // The track stays out. Its clips are not registered, so it is never asked about.
      }
    }
    if (verified.isEmpty) return 0;
    await db.transaction(() async {
      await store.upsertCatalog(verified);
      for (final t in verified) {
        for (final (kind, clip) in [(ClipKind.intro, t.intro), (ClipKind.middle, t.middle)]) {
          await store.registerClip(
            trackId: t.id,
            kind: kind,
            path: ClipStore.starterPath(t.id, kind),
            bytes: clip.bytes,
            source: ClipSource.starter,
            // A clip already there stays: a pack's copy or a prefetched copy is as good.
            replace: false,
          );
        }
      }
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: markerKey, value: marker),
          );
    });
    return verified.length;
  }

  /// Checks the starter clips on the device against the bundled manifest. One whose file is gone
  /// or no longer matches is marked broken: it is not played again until an app update brings a
  /// new starter pack (or a download replaces it). Returns how many failed. Never throws.
  Future<int> checkClips() async {
    try {
      final manifest = PackManifest.parse(await _bundle.loadString('$starterAssetDir/manifest.json'));
      final byId = {for (final t in manifest.tracks) t.id: t};
      final rows = await (db.select(db.clips)
            ..where((t) => t.source.equals(ClipSource.starter) & t.broken.equals(false)))
          .get();
      final base = await supportDirectory();
      var failed = 0;
      for (final row in rows) {
        final track = byId[row.trackId];
        if (track == null) continue;
        final kind = ClipKind.values.byName(row.kind);
        final clip = kind == ClipKind.intro ? track.intro : track.middle;
        final file = File(p.join(base.path, row.path));
        if (await file.exists() && await fileHasSha256(file, clip.sha256)) continue;
        await store.markBroken(row.trackId, kind);
        failed++;
      }
      return failed;
    } catch (_) {
      return 0; // No starter pack in this build, or it cannot be read: nothing to check.
    }
  }

  /// Every starter track has a clip row. False after a "Clear cache" would be wrong, since that
  /// leaves starter clips alone, but a missing row is repaired on the next start all the same.
  Future<bool> _allRegistered(PackManifest manifest) async {
    final rows = await db.select(db.clips).get();
    final have = {for (final r in rows) (r.trackId, r.kind)};
    return manifest.tracks.every(
      (t) => have.contains((t.id, ClipKind.intro.name)) && have.contains((t.id, ClipKind.middle.name)),
    );
  }

  Future<void> _copy(Directory base, int trackId, ClipKind kind, ManifestClip clip) async {
    final target = File(p.join(base.path, ClipStore.starterPath(trackId, kind)));
    if (await target.exists() && await fileHasSha256(target, clip.sha256)) return;
    final data = await _bundle.load('$starterAssetDir/clips/$trackId-${kind.name}.mp3');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    if (!await fileHasSha256(target, clip.sha256)) {
      await target.delete();
      throw StateError('starter clip $trackId ${kind.name} does not match its checksum');
    }
  }
}
