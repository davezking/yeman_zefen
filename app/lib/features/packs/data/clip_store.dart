import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/db/app_db.dart';
import '../../game/domain/session_config.dart';
import 'pack_manifest.dart';

/// The two clips every track has. Its name is the `kind` column and the file name part.
enum ClipKind {
  intro,
  middle;

  /// The clip a game mode plays. The generation mode has no clip of its own yet and uses the intro.
  static ClipKind forMode(GameMode mode) => mode == GameMode.middle ? middle : intro;
}

/// How much space the clips on the device take, by where they came from.
class StorageUsage {
  const StorageUsage({this.starterBytes = 0, this.streamBytes = 0, this.packBytes = 0});

  final int starterBytes;
  final int streamBytes;
  final int packBytes;

  int get totalBytes => starterBytes + streamBytes + packBytes;

  @override
  bool operator ==(Object other) =>
      other is StorageUsage &&
      other.starterBytes == starterBytes &&
      other.streamBytes == streamBytes &&
      other.packBytes == packBytes;

  @override
  int get hashCode => Object.hash(starterBytes, streamBytes, packBytes);
}

/// The catalog and the clip files on the device, as rows in `catalog_tracks` and `clips`.
///
/// Rules this class holds: a `clips` row exists only for a file whose SHA-256 matched; `starter`
/// and `pack` clips are never evicted; only `stream` clips count against the cache cap.
class ClipStore {
  ClipStore({
    required this.db,
    required this.supportDirectory,
    int Function()? nowMs,
    Future<void> Function(File file)? deleteFile,
  })  : _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
        _deleteFile = deleteFile ?? _deleteQuietly;

  final AppDb db;
  final Future<Directory> Function() supportDirectory;
  final int Function() _nowMs;
  final Future<void> Function(File file) _deleteFile;

  /// The default cap for `stream` clips.
  static const defaultStreamCacheCapBytes = 50 * 1024 * 1024;

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A file that stays only takes space; the row is what the game goes by.
    }
  }

  /// Where a prefetched clip goes, relative to the support directory.
  static String streamPath(int trackId, ClipKind kind) => 'stream/$trackId-${kind.name}.mp3';

  /// Where a bundled clip is copied to, relative to the support directory.
  static String starterPath(int trackId, ClipKind kind) => 'starter/$trackId-${kind.name}.mp3';

  /// Adds the tracks to the catalog, replacing a track that is already there (a newer manifest
  /// knows its clips better). Clip rows are not touched.
  Future<void> upsertCatalog(Iterable<ManifestTrack> tracks) async {
    final now = _nowMs();
    await db.batch((b) {
      for (final t in tracks) {
        b.insert(
          db.catalogTracks,
          CatalogTracksCompanion.insert(
            id: Value(t.id),
            titleAm: Value(t.titleAm),
            titleLatin: Value(t.titleLatin),
            artistId: t.artistId,
            artistAm: Value(t.artistAm),
            artistLatin: Value(t.artistLatin),
            generationId: Value(t.generationId),
            releaseYear: Value(t.releaseYear),
            introUrl: Value(t.intro.url),
            introSha256: Value(t.intro.sha256),
            introBytes: Value(t.intro.bytes),
            middleUrl: Value(t.middle.url),
            middleSha256: Value(t.middle.sha256),
            middleBytes: Value(t.middle.bytes),
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Records a verified clip file. With [replace] false a `starter` or `pack` row that is already
  /// there stays (a bundled clip never downgrades a pack's), while a prefetched `stream` row is
  /// replaced and its file removed, so the clip is not kept twice.
  Future<void> registerClip({
    required int trackId,
    required ClipKind kind,
    required String path,
    required int bytes,
    required String source,
    bool replace = true,
  }) async {
    if (!replace) {
      final old = await (db.select(db.clips)
            ..where((t) => t.trackId.equals(trackId) & t.kind.equals(kind.name) & t.source.equals(ClipSource.stream)))
          .getSingleOrNull();
      if (old != null && old.path != path) {
        await forget(trackId, kind);
        await _deleteFile(File(p.join((await supportDirectory()).path, old.path)));
      }
    }
    await db.into(db.clips).insert(
          ClipsCompanion.insert(
            trackId: trackId,
            kind: kind.name,
            path: path,
            bytes: bytes,
            source: source,
            lastPlayedAt: _nowMs(),
          ),
          mode: replace ? InsertMode.insertOrReplace : InsertMode.insertOrIgnore,
        );
  }

  /// Drops a clip row whose file turned out to be gone, so the clip counts as not on the device.
  Future<void> forget(int trackId, ClipKind kind) {
    return (db.delete(db.clips)..where((t) => t.trackId.equals(trackId) & t.kind.equals(kind.name))).go();
  }

  /// Marks a clip as played now, which is what the cache evicts by.
  Future<void> touch(int trackId, ClipKind kind) {
    return (db.update(db.clips)..where((t) => t.trackId.equals(trackId) & t.kind.equals(kind.name)))
        .write(ClipsCompanion(lastPlayedAt: Value(_nowMs())));
  }

  /// Deletes `stream` clips, least recently played first, until they fit in [capBytes]. Returns
  /// how many bytes were freed. `starter` and `pack` clips are never touched.
  Future<int> evict(int capBytes) async {
    final rows = await (db.select(db.clips)
          ..where((t) => t.source.equals(ClipSource.stream))
          ..orderBy([(t) => OrderingTerm.asc(t.lastPlayedAt), (t) => OrderingTerm.asc(t.trackId)]))
        .get();
    var total = rows.fold<int>(0, (sum, r) => sum + r.bytes);
    if (total <= capBytes) return 0;
    final base = await supportDirectory();
    var freed = 0;
    for (final row in rows) {
      if (total <= capBytes) break;
      await forget(row.trackId, ClipKind.values.byName(row.kind));
      await _deleteFile(File(p.join(base.path, row.path)));
      total -= row.bytes;
      freed += row.bytes;
    }
    return freed;
  }

  /// Deletes every `stream` clip (Settings → Clear cache). Starter and pack clips stay.
  Future<void> clearStreamCache() async {
    final rows = await (db.select(db.clips)..where((t) => t.source.equals(ClipSource.stream))).get();
    final base = await supportDirectory();
    await (db.delete(db.clips)..where((t) => t.source.equals(ClipSource.stream))).go();
    for (final row in rows) {
      await _deleteFile(File(p.join(base.path, row.path)));
    }
  }

  Stream<StorageUsage> watchUsage() => db.select(db.clips).watch().map(_usageOf);

  Future<StorageUsage> usage() async => _usageOf(await db.select(db.clips).get());

  static StorageUsage _usageOf(List<Clip> rows) {
    var starter = 0;
    var stream = 0;
    var pack = 0;
    for (final r in rows) {
      switch (r.source) {
        case ClipSource.starter:
          starter += r.bytes;
        case ClipSource.stream:
          stream += r.bytes;
        case ClipSource.pack:
          pack += r.bytes;
      }
    }
    return StorageUsage(starterBytes: starter, streamBytes: stream, packBytes: pack);
  }
}
