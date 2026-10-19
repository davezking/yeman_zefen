import 'package:drift/drift.dart';

import '../../../core/db/app_db.dart';
import 'clip_store.dart';
import 'pack_installer.dart';
import 'starter_pack.dart';

/// Checks the clip files on the device against their checksums, in the background after start,
/// so a file damaged on disk is found before a game reaches it.
///
/// - Each installed pack: once for each version it is installed at, then weekly, and on every
///   start while one of its clips is broken. A bad file is downloaded again (see
///   [PackInstaller.check]); offline it is marked broken and the check stays due.
/// - Cached (`stream`) clips: weekly. A bad one is dropped and fetched again when needed.
/// - Starter clips: weekly. A bad one is marked broken until the next app update.
///
/// When each check last ran is kept in `app_settings`.
class ClipChecker {
  ClipChecker({
    required this.db,
    required this.store,
    required this.installer,
    required this.starter,
    required this.allowDownloads,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDb db;
  final ClipStore store;
  final PackInstaller installer;
  final StarterPack starter;

  /// Whether a bad pack clip may be downloaded again now.
  final Future<bool> Function() allowDownloads;
  final int Function() _nowMs;

  static const interval = Duration(days: 7);
  static const streamKey = 'clip_check:stream';
  static const starterKey = 'clip_check:starter';
  static String packKey(String slug) => 'clip_check:pack:$slug';

  Future<void>? _running;

  /// Runs the checks that are due. A call while one runs waits for it. Never throws.
  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    try {
      final now = _nowMs();
      final saved = {for (final r in await db.select(db.appSettings).get()) r.key: r.value};
      bool weeklyDue(String key) {
        final last = int.tryParse(saved[key] ?? '');
        return last == null || now - last >= interval.inMilliseconds;
      }

      if (weeklyDue(starterKey)) {
        await starter.checkClips();
        await _save(starterKey, '$now');
      }
      if (weeklyDue(streamKey)) {
        await store.checkStreamClips();
        await _save(streamKey, '$now');
      }

      bool? downloads;
      for (final pack in await db.select(db.installedPacks).get()) {
        final key = packKey(pack.slug);
        final (version, at) = _parsePackMark(saved[key]);
        final broken = await (db.select(db.clips)
              ..where((c) => c.broken.equals(true) & c.path.like('packs/${pack.slug}/%'))
              ..limit(1))
            .getSingleOrNull();
        final due = version != pack.version || now - at >= interval.inMilliseconds || broken != null;
        if (!due) continue;
        downloads ??= await _allowDownloads();
        final complete = await installer.check(pack.slug, allowDownloads: downloads);
        if (complete) await _save(key, '${pack.version}:$now');
      }
    } catch (_) {
      // Checked again on the next start.
    }
  }

  Future<bool> _allowDownloads() async {
    try {
      return await allowDownloads();
    } catch (_) {
      return false;
    }
  }

  static (int?, int) _parsePackMark(String? value) {
    final parts = value?.split(':');
    if (parts == null || parts.length != 2) return (null, 0);
    return (int.tryParse(parts[0]), int.tryParse(parts[1]) ?? 0);
  }

  Future<void> _save(String key, String value) =>
      db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
}
