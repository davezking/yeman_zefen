import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/db/app_db.dart';
import '../domain/pack_install_progress.dart';
import 'checksum.dart';
import 'clip_downloader.dart';
import 'clip_store.dart';
import 'pack_manifest.dart';

class PackInstallException implements Exception {
  const PackInstallException(this.message);
  final String message;

  @override
  String toString() => 'PackInstallException: $message';
}

/// Installs a pack: downloads every clip, verifies each against its checksum,
/// then registers the pack in one transaction. A pack is either fully installed
/// or not registered at all.
///
/// Files live in `packs/{slug}/v{version}/` under the support directory. The
/// database stores paths relative to that directory, because iOS changes the
/// absolute container path across app updates.
class PackInstaller {
  PackInstaller({
    required this.db,
    required this.downloader,
    required this.supportDirectory,
    this.maxParallelDownloads = 4,
    this.maxDownloadAttempts = 3,
    Future<void> Function(Directory dir)? deleteDirectory,
  })  : _deleteDirectory = deleteDirectory ?? _deleteRecursively,
        _store = ClipStore(db: db, supportDirectory: supportDirectory);

  final AppDb db;
  final ClipDownloader downloader;
  final Future<Directory> Function() supportDirectory;

  final int maxParallelDownloads;

  /// Downloads per file, including the first. 3 means one try and two re-fetches.
  final int maxDownloadAttempts;

  final ClipStore _store;

  /// Removes an old version's folder. Replaceable so a test can make it fail.
  final Future<void> Function(Directory dir) _deleteDirectory;

  static Future<void> _deleteRecursively(Directory dir) async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// The install running or queued for each slug.
  final _running = <String, Future<void>>{};

  final _controller = StreamController<PackInstallProgress>.broadcast();
  final _latest = <String, PackInstallProgress>{};

  /// Progress for one pack. A new subscriber first gets the latest state, so a
  /// screen that opens mid-install does not start blank.
  Stream<PackInstallProgress> progressFor(String slug) async* {
    final last = _latest[slug];
    if (last != null) yield last;
    yield* _controller.stream.where((event) => event.slug == slug);
  }

  Future<void> dispose() => _controller.close();

  /// The installed version of a pack, or null when it is not installed.
  Future<int?> installedVersion(String slug) async {
    final row = await (db.select(db.installedPacks)
          ..where((t) => t.slug.equals(slug)))
        .getSingleOrNull();
    return row?.version;
  }

  /// Installs [manifest], whose exact text is [manifestJson]. It must be the
  /// pack and version that were asked for, [expectedSlug] and [expectedVersion],
  /// as listed by `GET /v1/packs`.
  ///
  /// Throws [PackInstallException] on failure. In that case the previously
  /// installed version, if any, is left as it was. Installs of the same pack run
  /// one after another, because two at once would write the same files.
  Future<void> install(
    PackManifest manifest,
    String manifestJson, {
    required String expectedSlug,
    required int expectedVersion,
  }) {
    final previous = _running[expectedSlug] ?? Future<void>.value();
    final run = previous.then(
      (_) => _install(manifest, manifestJson, expectedSlug, expectedVersion),
    );
    // The queue moves on whether this one succeeds or fails.
    final settled = run.then<void>((_) {}, onError: (Object _) {});
    _running[expectedSlug] = settled;
    unawaited(settled.then((_) {
      if (identical(_running[expectedSlug], settled)) _running.remove(expectedSlug);
    }));
    return run;
  }

  Future<void> _install(
    PackManifest manifest,
    String manifestJson,
    String expectedSlug,
    int expectedVersion,
  ) async {
    final slug = manifest.slug;
    String? problem;
    if (slug != expectedSlug || manifest.version != expectedVersion) {
      problem = 'manifest is $slug v${manifest.version}, expected $expectedSlug v$expectedVersion';
    } else if (!isValidPackSlug(slug)) {
      problem = '"$slug" is not a valid pack slug';
    }
    if (problem != null) {
      _emit(PackInstallProgress(slug: expectedSlug, state: PackInstallState.failed, error: problem));
      throw PackInstallException(problem);
    }

    final paths = _TrackPaths.of(manifest);
    final files = [
      for (final t in manifest.tracks) ...[
        _ClipFile(relativePath: paths.intro(t.id), clip: t.intro),
        _ClipFile(relativePath: paths.middle(t.id), clip: t.middle),
      ],
    ];
    final tracker = _Tracker(
      slug: slug,
      bytesTotal: files.fold(0, (sum, f) => sum + f.clip.bytes),
      filesTotal: files.length,
      emit: _emit,
    );

    _emit(tracker.snapshot(PackInstallState.queued));
    final Directory base;
    final int? previousVersion;
    List<Clip> replacedStream = const [];
    try {
      base = await supportDirectory();
      previousVersion = await installedVersion(slug);

      await _forEachLimited(files, maxParallelDownloads, (file) {
        return _fetchVerified(base, file, tracker);
      });
      replacedStream = await _register(manifest, manifestJson, paths);
    } catch (e) {
      final message = e is PackInstallException ? e.message : '$e';
      _emit(tracker.snapshot(PackInstallState.failed, error: message));
      throw PackInstallException(message);
    }

    // The new version is installed. The old folder is removed only now, so a
    // failed install never breaks the installed pack. If removing it fails, the
    // install still succeeded: the folder only takes space.
    if (previousVersion != null && previousVersion != manifest.version) {
      try {
        await _deleteDirectory(Directory(p.join(base.path, 'packs', slug, 'v$previousVersion')));
      } catch (_) {}
    }
    // The pack's own files now stand in for prefetched copies of the same clips, which only
    // take space (and are outside the cache cap once their rows are gone).
    for (final clip in replacedStream) {
      try {
        final file = File(p.join(base.path, clip.path));
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _emit(tracker.snapshot(PackInstallState.installed));
  }

  /// Downloads [file] and checks its SHA-256. Re-fetches on a mismatch, up to
  /// [maxDownloadAttempts] downloads. A file that already verifies is kept, so
  /// an install that was interrupted continues where it stopped.
  Future<void> _fetchVerified(Directory base, _ClipFile file, _Tracker tracker) async {
    final target = File(p.join(base.path, file.relativePath));
    var downloads = 0;
    while (true) {
      if (await target.exists()) {
        tracker.verifying(file.relativePath);
        if (await fileHasSha256(target, file.clip.sha256)) {
          tracker.fileDone(file.relativePath, file.clip.bytes);
          return;
        }
        await target.delete();
      }
      if (downloads == maxDownloadAttempts) {
        throw PackInstallException(
          'checksum mismatch for ${file.relativePath} after $downloads downloads',
        );
      }
      downloads++;
      await target.parent.create(recursive: true);
      tracker.downloading(file.relativePath);
      await downloader.download(
        url: file.clip.url,
        relativePath: file.relativePath,
        onProgress: (fraction) => tracker.inFlight(
          file.relativePath,
          (fraction * file.clip.bytes).round(),
        ),
      );
    }
  }

  /// Registers the pack in one transaction. The previous row and its tracks are
  /// replaced only here, so a failure above leaves them untouched. The tracks also go into the
  /// catalog, and each clip becomes a `pack` clip (replacing a prefetched `stream` copy, which is
  /// returned so its file can be removed).
  Future<List<Clip>> _register(PackManifest m, String manifestJson, _TrackPaths paths) {
    return db.transaction(() async {
      await (db.delete(db.localTracks)..where((t) => t.packSlug.equals(m.slug))).go();
      await db.into(db.installedPacks).insertOnConflictUpdate(
            InstalledPacksCompanion.insert(
              slug: m.slug,
              version: m.version,
              manifestJson: manifestJson,
              installedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
              totalBytes: m.totalBytes,
            ),
          );
      await db.batch((b) {
        b.insertAll(db.localTracks, [
          for (final t in m.tracks)
            LocalTracksCompanion.insert(
              packSlug: m.slug,
              id: t.id,
              titleAm: Value(t.titleAm),
              titleLatin: Value(t.titleLatin),
              artistAm: Value(t.artistAm),
              artistLatin: Value(t.artistLatin),
              artistId: Value(t.artistId),
              generationId: Value(t.generationId),
              releaseYear: Value(t.releaseYear),
              introPath: Value(paths.intro(t.id)),
              middlePath: Value(paths.middle(t.id)),
            ),
        ]);
      });
      await _store.upsertCatalog(m.tracks);
      // Clips of the version being replaced, including tracks the new version dropped.
      await (db.delete(db.clips)
            ..where((c) => c.source.equals(ClipSource.pack) & c.path.like('packs/${m.slug}/%')))
          .go();
      final ids = [for (final t in m.tracks) t.id];
      final replaced = await (db.select(db.clips)
            ..where((c) => c.trackId.isIn(ids) & c.source.equals(ClipSource.stream)))
          .get();
      for (final t in m.tracks) {
        await _store.registerClip(
          trackId: t.id,
          kind: ClipKind.intro,
          path: paths.intro(t.id),
          bytes: t.intro.bytes,
          source: ClipSource.pack,
        );
        await _store.registerClip(
          trackId: t.id,
          kind: ClipKind.middle,
          path: paths.middle(t.id),
          bytes: t.middle.bytes,
          source: ClipSource.pack,
        );
      }
      return replaced;
    });
  }

  void _emit(PackInstallProgress event) {
    _latest[event.slug] = event;
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Runs [action] over [items] with at most [limit] running at once. Once one
  /// item fails, no new items start; the first failure is rethrown after the
  /// running ones finish.
  static Future<void> _forEachLimited<T>(
    List<T> items,
    int limit,
    Future<void> Function(T item) action,
  ) async {
    var next = 0;
    var failed = false;
    Future<void> worker() async {
      while (!failed && next < items.length) {
        final item = items[next++];
        try {
          await action(item);
        } catch (_) {
          failed = true;
          rethrow;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < limit && i < items.length; i++) worker(),
    ]);
  }
}

/// Where a version's clip files go, relative to the support directory. The
/// downloads and the database both take paths from here.
class _TrackPaths {
  const _TrackPaths(this._dir);

  factory _TrackPaths.of(PackManifest m) => _TrackPaths('packs/${m.slug}/v${m.version}');

  final String _dir;

  String intro(int trackId) => '$_dir/$trackId-intro.mp3';
  String middle(int trackId) => '$_dir/$trackId-middle.mp3';
}

class _ClipFile {
  const _ClipFile({required this.relativePath, required this.clip});
  final String relativePath;
  final ManifestClip clip;
}

/// Keeps per-file byte counts and turns them into progress snapshots.
class _Tracker {
  _Tracker({
    required this.slug,
    required this.bytesTotal,
    required this.filesTotal,
    required this.emit,
  });

  final String slug;
  final int bytesTotal;
  final int filesTotal;
  final void Function(PackInstallProgress) emit;

  final _fileBytes = <String, int>{};
  final _doneFiles = <String>{};
  PackInstallState _state = PackInstallState.queued;

  PackInstallProgress snapshot(PackInstallState state, {String? error}) {
    _state = state;
    return PackInstallProgress(
      slug: slug,
      state: state,
      bytesDone: _fileBytes.values.fold(0, (a, b) => a + b),
      bytesTotal: bytesTotal,
      filesDone: _doneFiles.length,
      filesTotal: filesTotal,
      error: error,
    );
  }

  void downloading(String file) => _update(file, PackInstallState.downloading);
  void verifying(String file) => _update(file, PackInstallState.verifying);

  void inFlight(String file, int bytes) {
    _fileBytes[file] = bytes;
    emit(snapshot(_state));
  }

  void fileDone(String file, int bytes) {
    _fileBytes[file] = bytes;
    _doneFiles.add(file);
    emit(snapshot(_state));
  }

  void _update(String file, PackInstallState state) {
    _fileBytes.putIfAbsent(file, () => 0);
    emit(snapshot(state));
  }
}
