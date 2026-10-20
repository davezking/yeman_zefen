import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:path/path.dart' as p;

import '../../../core/crash/crash_reporting.dart';
import '../../../core/db/app_db.dart';
import '../domain/pack_install_progress.dart';
import 'checksum.dart';
import 'clip_downloader.dart';
import 'clip_store.dart';
import 'pack_manifest.dart';

/// Why an install failed, as far as the player is told.
enum PackInstallFailure {
  /// A download did not finish, or the manifest could not be used.
  other,

  /// A file kept failing its checksum after every re-fetch.
  checksum,

  /// The phone ran out of space.
  storageFull,

  /// The player cancelled it.
  cancelled,
}

class PackInstallException implements Exception {
  const PackInstallException(this.message, {this.failure = PackInstallFailure.other, this.missingBytes});
  final String message;
  final PackInstallFailure failure;

  /// For [PackInstallFailure.storageFull]: the bytes the install still had to write.
  final int? missingBytes;

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
    ClipStore? store,
    Future<void> Function(Directory dir)? deleteDirectory,
  })  : _deleteDirectory = deleteDirectory ?? _deleteRecursively,
        _store = store ?? ClipStore(db: db, supportDirectory: supportDirectory);

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

  /// The install or removal running or queued for each slug.
  final _running = <String, Future<void>>{};

  /// Installs not yet finished, by slug, so [cancel] can stop them.
  final _pending = <String, List<_Run>>{};

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
  /// one after another, because two at once would write the same files. With
  /// [wifiOnly] the downloads wait for Wi-Fi rather than use mobile data, also
  /// when the phone moves from Wi-Fi to mobile data during the install.
  Future<void> install(
    PackManifest manifest,
    String manifestJson, {
    required String expectedSlug,
    required int expectedVersion,
    bool wifiOnly = false,
  }) {
    final token = _Run(wifiOnly: wifiOnly);
    (_pending[expectedSlug] ??= []).add(token);
    return _enqueue(expectedSlug, () async {
      try {
        await _install(manifest, manifestJson, expectedSlug, expectedVersion, token);
      } finally {
        _pending[expectedSlug]?.remove(token);
      }
    });
  }

  /// Stops the installs of [slug] that are running or queued, including the downloads already
  /// under way. Clips that already verified stay in the folder, so downloading the pack again
  /// continues from there. An update that is cancelled leaves the installed version as it was.
  void cancel(String slug) {
    final runs = _pending[slug] ?? const <_Run>[];
    if (runs.isEmpty) return;
    for (final run in runs) {
      run.cancelled = true;
    }
    unawaited(downloader.cancelGroup(_downloadGroup(slug)).catchError((Object _) {}));
  }

  /// The downloads of one pack, which [cancel] stops together.
  static String _downloadGroup(String slug) => 'pack:$slug';

  /// Runs [action] after everything queued for [slug], because two at once would write the
  /// same files.
  Future<T> _enqueue<T>(String slug, Future<T> Function() action) {
    final previous = _running[slug] ?? Future<void>.value();
    final run = previous.then((_) => action());
    // The queue moves on whether this one succeeds or fails.
    final settled = run.then<void>((_) {}, onError: (Object _) {});
    _running[slug] = settled;
    unawaited(settled.then((_) {
      if (identical(_running[slug], settled)) _running.remove(slug);
    }));
    return run;
  }

  Future<void> _install(
    PackManifest manifest,
    String manifestJson,
    String expectedSlug,
    int expectedVersion,
    _Run token,
  ) async {
    final slug = manifest.slug;
    String? problem;
    if (slug != expectedSlug || manifest.version != expectedVersion) {
      problem = 'manifest is $slug v${manifest.version}, expected $expectedSlug v$expectedVersion';
    } else if (!isValidPackSlug(slug)) {
      problem = '"$slug" is not a valid pack slug';
    }
    if (problem != null) {
      final failure = PackInstallException(problem);
      _emit(PackInstallProgress(slug: expectedSlug, state: PackInstallState.failed, error: problem));
      recordNonFatal(failure, StackTrace.current, reason: 'pack_install_failed');
      throw failure;
    }

    final paths = _TrackPaths.of(manifest);
    final files = [
      for (final t in manifest.tracks) ...[
        _ClipFile(slug: slug, trackId: t.id, kind: ClipKind.intro, relativePath: paths.intro(t.id), clip: t.intro),
        _ClipFile(slug: slug, trackId: t.id, kind: ClipKind.middle, relativePath: paths.middle(t.id), clip: t.middle),
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

      // The clips already on the phone for this pack's tracks, read once.
      final onPhone = {
        for (final c in await (db.select(db.clips)
              ..where((c) => c.trackId.isIn({for (final t in manifest.tracks) t.id})))
            .get())
          (c.trackId, c.kind): c,
      };
      await _forEachLimited(files, maxParallelDownloads, (file) {
        _checkCancelled(token);
        return _fetchVerified(base, file, tracker, token, onPhone[(file.trackId, file.kind.name)]);
      });
      _checkCancelled(token);
      replacedStream = await _register(manifest, manifestJson, paths);
    } catch (e, stack) {
      PackInstallException storageFull() => PackInstallException(
            '$e',
            failure: PackInstallFailure.storageFull,
            missingBytes: tracker.bytesTotal - tracker.bytesDone,
          );
      final failure = switch (e) {
        // A cancelled download fails like any other; it was the player's choice.
        _ when token.cancelled => const PackInstallException('cancelled', failure: PackInstallFailure.cancelled),
        PackInstallException() => e,
        ClipDownloadException(noSpace: true) => storageFull(),
        FileSystemException(osError: OSError(errorCode: _noSpaceLeft)) => storageFull(),
        SqliteException(resultCode: _sqliteFull) => storageFull(),
        // The database runs on a background isolate, which wraps its errors.
        DriftRemoteException(remoteCause: SqliteException(resultCode: _sqliteFull)) => storageFull(),
        _ => PackInstallException('$e'),
      };
      final state = failure.failure == PackInstallFailure.cancelled
          ? PackInstallState.cancelled
          : PackInstallState.failed;
      _emit(tracker.snapshot(state, error: failure.message));
      // A full phone is the player's to fix, not a bug.
      if (state == PackInstallState.failed && failure.failure != PackInstallFailure.storageFull) {
        recordNonFatal(failure, stack, reason: 'pack_install_failed');
      }
      throw failure;
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

  /// ENOSPC on Linux and Android, and on iOS and macOS.
  static const _noSpaceLeft = 28;

  /// SQLITE_FULL: the database could not grow.
  static const _sqliteFull = 13;

  static void _checkCancelled(_Run token) {
    if (token.cancelled) {
      throw const PackInstallException('cancelled', failure: PackInstallFailure.cancelled);
    }
  }

  /// Downloads [file] and checks its SHA-256. Re-fetches on a mismatch, up to
  /// [maxDownloadAttempts] downloads. A file that already verifies is kept, so
  /// an install that was interrupted continues where it stopped, and the clip
  /// already on the phone ([onPhone]: prefetched, built in, or in the version
  /// being updated) is used instead of a download when it matches.
  Future<void> _fetchVerified(
    Directory base,
    _ClipFile file,
    _Tracker tracker,
    _Run token,
    Clip? onPhone,
  ) async {
    // A built-in clip stays the one that plays (see [_register]): a copy would only take space.
    // A broken one does not, so the pack's own file is fetched.
    if (onPhone != null && onPhone.source == ClipSource.starter && !onPhone.broken) {
      tracker.fileDone(file.relativePath, file.clip.bytes);
      return;
    }
    final target = File(p.join(base.path, file.relativePath));
    if (onPhone != null && !await target.exists()) await _reuseFromPhone(base, onPhone, target);
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
          failure: PackInstallFailure.checksum,
        );
      }
      downloads++;
      await target.parent.create(recursive: true);
      // Checked again here, after the awaits above: a download that starts after [cancel] would
      // not be among those it stopped.
      _checkCancelled(token);
      tracker.downloading(file.relativePath);
      await downloader.download(
        url: file.clip.url,
        relativePath: file.relativePath,
        onProgress: (fraction) => tracker.inFlight(
          file.relativePath,
          (fraction * file.clip.bytes).round(),
        ),
        group: _downloadGroup(file.slug),
        wifiOnly: token.wifiOnly,
      );
    }
  }

  /// Copies the clip [row] already on the phone (prefetched, or another version's) to [target].
  /// The caller checks it against the manifest's SHA-256 like a download, so a clip that changed
  /// since is simply downloaded. Copied, not moved: a game may be playing it, and an install that
  /// fails or is cancelled must leave it where it was. A prefetched copy is deleted once the pack
  /// is registered.
  Future<void> _reuseFromPhone(Directory base, Clip row, File target) async {
    if (p.join(base.path, row.path) == target.path) return;
    final source = File(p.join(base.path, row.path));
    try {
      if (!await source.exists()) return;
      await target.parent.create(recursive: true);
      await source.copy(target.path);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == _noSpaceLeft) rethrow;
      // Anything else: the clip is downloaded instead.
    }
  }

  /// Checks every clip of the installed pack [slug] against the manifest it was installed from,
  /// and fixes what it can. A clip whose file is missing, fails its checksum, or is marked broken
  /// is downloaded again when [allowDownloads] is set, and otherwise marked broken so no game plays
  /// it. A good file whose row is missing or points elsewhere (a prefetched copy took its place) is
  /// registered as the pack's again. A clip the pack does not supply (a built-in one, or another
  /// installed pack's file) is left alone.
  ///
  /// Returns true when every clip of the pack is now good, false when one still needs a download.
  /// Runs after any install or removal of the same pack, never alongside it. Not installed: true.
  Future<bool> check(String slug, {required bool allowDownloads}) =>
      _enqueue(slug, () => _check(slug, allowDownloads));

  Future<bool> _check(String slug, bool allowDownloads) async {
    final installed = await (db.select(db.installedPacks)..where((t) => t.slug.equals(slug))).getSingleOrNull();
    if (installed == null) return true;
    final PackManifest manifest;
    try {
      manifest = PackManifest.parse(installed.manifestJson);
    } on PackManifestException {
      return true; // Nothing to check against.
    }
    final base = await supportDirectory();
    final paths = _TrackPaths.of(manifest);
    final onPhone = {
      for (final c in await (db.select(db.clips)..where((c) => c.trackId.isIn({for (final t in manifest.tracks) t.id})))
          .get())
        (c.trackId, c.kind): c,
    };
    var complete = true;
    for (final t in manifest.tracks) {
      for (final (kind, path, clip) in [
        (ClipKind.intro, paths.intro(t.id), t.intro),
        (ClipKind.middle, paths.middle(t.id), t.middle),
      ]) {
        final row = onPhone[(t.id, kind.name)];
        if (row != null && !row.broken && row.path != path && row.source != ClipSource.stream) continue;
        final target = File(p.join(base.path, path));
        // A broken file is downloaded again even when it matches: it would not play.
        var good = !(row != null && row.broken && row.path == path) &&
            await target.exists() &&
            await fileHasSha256(target, clip.sha256);
        if (!good && allowDownloads) good = await _refetch(base, slug, path, clip);
        if (good) {
          if (row == null || row.broken || row.path != path) {
            await _store.registerClip(trackId: t.id, kind: kind, path: path, bytes: clip.bytes, source: ClipSource.pack);
            if (row != null && row.source == ClipSource.stream && row.path != path) {
              try {
                final old = File(p.join(base.path, row.path));
                if (await old.exists()) await old.delete();
              } catch (_) {}
            }
          }
        } else {
          complete = false;
          if (row != null && row.path == path) await _store.markBroken(t.id, kind);
        }
      }
    }
    return complete;
  }

  /// Downloads a pack clip again, next to its file, and moves it into place only once it
  /// verifies, so a game playing the old file is not cut off mid-download. False when it never
  /// verified or could not be downloaded.
  Future<bool> _refetch(Directory base, String slug, String path, ManifestClip clip) async {
    final partPath = '$path.part';
    final part = File(p.join(base.path, partPath));
    try {
      for (var attempt = 0; attempt < maxDownloadAttempts; attempt++) {
        if (await part.exists()) await part.delete();
        await part.parent.create(recursive: true);
        await downloader.download(url: clip.url, relativePath: partPath, onProgress: (_) {}, group: _downloadGroup(slug));
        if (await part.exists() && await fileHasSha256(part, clip.sha256)) {
          await part.rename(p.join(base.path, path));
          return true;
        }
      }
    } catch (_) {
      // Offline, cancelled, or out of space: the clip stays broken until the next check.
    }
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
    return false;
  }

  /// Removes an installed pack and frees its space. A clip that another installed pack also has
  /// is pointed at that pack's file. Every other clip moves into the stream cache, where the
  /// prefetcher can still use it and the cache cap applies (the caller trims the cache). Waits for
  /// an install of the same pack, and for a game in progress, to finish first.
  Future<void> remove(String slug) => _enqueue(slug, () => _remove(slug));

  Future<void> _remove(String slug) async {
    // A game in progress may be playing these files: they move only once it ends.
    await _store.idle();
    final base = await supportDirectory();
    final prefix = 'packs/$slug/';
    final packClips = await (db.select(db.clips)
          ..where((c) => c.source.equals(ClipSource.pack) & c.path.like('$prefix%')))
        .get();
    final elsewhere = {
      for (final t in await (db.select(db.localTracks)
            ..where((t) => t.id.isIn({for (final c in packClips) c.trackId}) & t.packSlug.equals(slug).not()))
          .get())
        t.id,
    };

    // The files move first. If the app stops before the rows change, a row points at a missing
    // file, which the game already handles by forgetting the clip.
    final moved = <Clip>[];
    for (final clip in packClips) {
      // A broken clip is not worth keeping in the cache: it goes with the pack.
      if (elsewhere.contains(clip.trackId) || clip.broken) continue;
      final kind = ClipKind.values.byName(clip.kind);
      final to = ClipStore.streamPath(clip.trackId, kind);
      try {
        final target = File(p.join(base.path, to));
        await target.parent.create(recursive: true);
        await File(p.join(base.path, clip.path)).rename(target.path);
        moved.add(clip.copyWith(path: to, source: ClipSource.stream));
      } on FileSystemException {
        // Gone already, or it cannot move: the clip is dropped with the pack.
      }
    }

    final previous = {for (final c in packClips) c.trackId};
    await db.transaction(() async {
      await (db.delete(db.clips)..where((c) => c.source.equals(ClipSource.pack) & c.path.like('$prefix%'))).go();
      await (db.delete(db.localTracks)..where((t) => t.packSlug.equals(slug))).go();
      await (db.delete(db.installedPacks)..where((t) => t.slug.equals(slug))).go();
      // Keeps when each clip was last played, which is what the cache evicts by.
      await db.batch((b) => b.insertAll(db.clips, moved, mode: InsertMode.insertOrReplace));
      await _keepOtherPacksClips(slug, previous.intersection(elsewhere));
    });
    try {
      await _deleteDirectory(Directory(p.join(base.path, 'packs', slug)));
    } catch (_) {
      // The rows are gone; a folder that stays only takes space.
    }
    _latest.remove(slug);
  }

  /// Registers the pack in one transaction. The previous row and its tracks are
  /// replaced only here, so a failure above leaves them untouched. The tracks also go into the
  /// catalog, and each clip becomes a `pack` clip (replacing a prefetched `stream` copy, which is
  /// returned so its file can be removed), except a built-in one, which stays `starter`.
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
      final previous = await (db.select(db.clips)
            ..where((c) => c.source.equals(ClipSource.pack) & c.path.like('packs/${m.slug}/%')))
          .get();
      await (db.delete(db.clips)
            ..where((c) => c.source.equals(ClipSource.pack) & c.path.like('packs/${m.slug}/%')))
          .go();
      final ids = [for (final t in m.tracks) t.id];
      final replaced = await (db.select(db.clips)
            ..where((c) => c.trackId.isIn(ids) & c.source.equals(ClipSource.stream)))
          .get();
      // A built-in clip keeps its row: it is never evicted, and stays when this pack is removed. A
      // broken one gives way to the pack's.
      final builtIn = {
        for (final c in await (db.select(db.clips)
              ..where((c) => c.trackId.isIn(ids) & c.source.equals(ClipSource.starter) & c.broken.equals(false)))
            .get())
          (c.trackId, c.kind),
      };
      for (final t in m.tracks) {
        for (final (kind, path, bytes) in [
          (ClipKind.intro, paths.intro(t.id), t.intro.bytes),
          (ClipKind.middle, paths.middle(t.id), t.middle.bytes),
        ]) {
          if (builtIn.contains((t.id, kind.name))) continue;
          await _store.registerClip(trackId: t.id, kind: kind, path: path, bytes: bytes, source: ClipSource.pack);
        }
      }
      await _keepOtherPacksClips(m.slug, {for (final c in previous) c.trackId}.difference(ids.toSet()));
      return replaced;
    });
  }

  /// A track this pack dropped (an update without it, or the pack removed) can still be in another
  /// installed pack. Its clip row pointed at this pack's files and is gone, so it is pointed at the
  /// other pack's files instead.
  Future<void> _keepOtherPacksClips(String slug, Set<int> dropped) async {
    if (dropped.isEmpty) return;
    final others = await (db.select(db.localTracks)
          ..where((t) => t.id.isIn(dropped) & t.packSlug.equals(slug).not()))
        .get();
    final catalog = {
      for (final t in await (db.select(db.catalogTracks)..where((t) => t.id.isIn(dropped))).get()) t.id: t,
    };
    for (final row in others) {
      for (final (kind, path, bytes) in [
        (ClipKind.intro, row.introPath, catalog[row.id]?.introBytes),
        (ClipKind.middle, row.middlePath, catalog[row.id]?.middleBytes),
      ]) {
        if (path == null) continue;
        await _store.registerClip(
          trackId: row.id,
          kind: kind,
          path: path,
          bytes: bytes ?? 0,
          source: ClipSource.pack,
          replace: false,
        );
      }
    }
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
  const _ClipFile({
    required this.slug,
    required this.trackId,
    required this.kind,
    required this.relativePath,
    required this.clip,
  });
  final String slug;
  final int trackId;
  final ClipKind kind;
  final String relativePath;
  final ManifestClip clip;
}

/// One install: [PackInstaller.cancel] marks it, and it stops before its next file.
class _Run {
  _Run({required this.wifiOnly});

  final bool wifiOnly;
  var cancelled = false;
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

  int get bytesDone => _fileBytes.values.fold(0, (a, b) => a + b);

  PackInstallProgress snapshot(PackInstallState state, {String? error}) {
    _state = state;
    return PackInstallProgress(
      slug: slug,
      state: state,
      bytesDone: bytesDone,
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
