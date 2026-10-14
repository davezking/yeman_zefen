import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/db/app_db.dart';
import '../domain/pack_install_progress.dart';
import 'clip_downloader.dart';
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
  });

  final AppDb db;
  final ClipDownloader downloader;
  final Future<Directory> Function() supportDirectory;

  final int maxParallelDownloads;

  /// Downloads per file, including the first. 3 means one try and two re-fetches.
  final int maxDownloadAttempts;

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

  /// Installs [manifest], whose exact text is [manifestJson]. Throws
  /// [PackInstallException] on failure. In that case the previously installed
  /// version, if any, is left as it was.
  Future<void> install(PackManifest manifest, String manifestJson) async {
    final slug = manifest.slug;
    final files = [
      for (final t in manifest.tracks) ...[
        _ClipFile(
          relativePath: 'packs/$slug/v${manifest.version}/${t.id}-intro.mp3',
          clip: t.intro,
        ),
        _ClipFile(
          relativePath: 'packs/$slug/v${manifest.version}/${t.id}-middle.mp3',
          clip: t.middle,
        ),
      ],
    ];
    final tracker = _Tracker(
      slug: slug,
      bytesTotal: files.fold(0, (sum, f) => sum + f.clip.bytes),
      filesTotal: files.length,
      emit: _emit,
    );

    _emit(tracker.snapshot(PackInstallState.queued));
    try {
      final base = await supportDirectory();
      final previousVersion = await installedVersion(slug);

      await _forEachLimited(files, maxParallelDownloads, (file) {
        return _fetchVerified(base, file, tracker);
      });
      await _register(manifest, manifestJson, files);

      // Only after the new version is registered. Removing the old files earlier
      // could break the installed pack if this install fails.
      if (previousVersion != null && previousVersion != manifest.version) {
        final oldDir = Directory(p.join(base.path, 'packs', slug, 'v$previousVersion'));
        if (await oldDir.exists()) await oldDir.delete(recursive: true);
      }
      _emit(tracker.snapshot(PackInstallState.installed));
    } catch (e) {
      final message = e is PackInstallException ? e.message : '$e';
      _emit(tracker.snapshot(PackInstallState.failed, error: message));
      throw PackInstallException(message);
    }
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
        if (await _matches(target, file.clip.sha256)) {
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
  /// replaced only here, so a failure above leaves them untouched.
  Future<void> _register(PackManifest m, String manifestJson, List<_ClipFile> files) {
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
              releaseYear: Value(t.releaseYear),
              introPath: Value('packs/${m.slug}/v${m.version}/${t.id}-intro.mp3'),
              middlePath: Value('packs/${m.slug}/v${m.version}/${t.id}-middle.mp3'),
            ),
        ]);
      });
    });
  }

  void _emit(PackInstallProgress event) {
    _latest[event.slug] = event;
    if (!_controller.isClosed) _controller.add(event);
  }

  static Future<bool> _matches(File file, String expectedSha256) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expectedSha256;
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
