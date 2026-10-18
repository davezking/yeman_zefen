import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/db/app_db.dart';
import '../../../core/l10n/display_name.dart';
import '../../packs/data/clip_store.dart';
import '../domain/game_track.dart';
import '../domain/session_config.dart';

/// Where to fetch a clip and what it must hash to.
class RemoteClip {
  const RemoteClip({required this.url, required this.sha256, required this.bytes});
  final String url;
  final String sha256;
  final int bytes;
}

/// The catalog as the round engine and the round screen need it: every track the app knows, what
/// to call each answer, and for each clip whether it is on the device or can be fetched.
class GameLibrary {
  GameLibrary._(this.tracks, this._rows, this._artistNames, this._clips, this._base);

  /// Builds a library from `catalog_tracks` and `clips` rows. Every catalog track is kept.
  factory GameLibrary.fromRows(Iterable<CatalogTrack> catalog, Iterable<Clip> clips, Directory base) {
    final byId = <int, CatalogTrack>{};
    final artistNames = <int, DisplayName>{};
    for (final row in catalog) {
      if (byId.containsKey(row.id)) continue;
      byId[row.id] = row;
      // The first track that has a name for the artist decides it.
      final name = DisplayName.of(row.artistAm, row.artistLatin);
      if (!name.isEmpty) artistNames.putIfAbsent(row.artistId, () => name);
    }
    return GameLibrary._(
      [
        for (final row in byId.values)
          GameTrack(id: row.id, artistId: row.artistId, generationId: row.generationId),
      ],
      byId,
      artistNames,
      {for (final c in clips) (c.trackId, c.kind): c},
      base,
    );
  }

  /// Every track in the catalog: the ones to ask about and the ones that only supply wrong answers.
  final List<GameTrack> tracks;
  final Map<int, CatalogTrack> _rows;
  final Map<int, DisplayName> _artistNames;
  final Map<(int, String), Clip> _clips;
  final Directory _base;

  bool get isEmpty => tracks.isEmpty;

  /// The eras that have at least one track.
  Set<int> get eras => {
        for (final t in tracks)
          if (t.generationId != null) t.generationId!,
      };

  /// The track's title in both scripts, resolved to the UI language when it is shown, so a
  /// language switch changes the screen at once. Empty when the catalog has no title.
  DisplayName trackName(int trackId) {
    final row = _rows[trackId];
    return row == null ? const DisplayName() : DisplayName.of(row.titleAm, row.titleLatin);
  }

  DisplayName artistName(int artistId) => _artistNames[artistId] ?? const DisplayName();

  /// A verified clip for [mode] is on the device (its file is checked when it is about to play).
  bool hasClip(int trackId, GameMode mode) => _clips.containsKey((trackId, ClipKind.forMode(mode).name));

  /// The absolute path of the clip for [mode] on the device, or null when it is not there.
  String? clipPath(int trackId, GameMode mode) {
    final clip = _clips[(trackId, ClipKind.forMode(mode).name)];
    return clip == null ? null : p.join(_base.path, clip.path);
  }

  /// Where to fetch the clip for [mode], or null when the catalog does not know.
  RemoteClip? remoteClip(int trackId, GameMode mode) {
    final row = _rows[trackId];
    if (row == null) return null;
    final middle = ClipKind.forMode(mode) == ClipKind.middle;
    final url = middle ? row.middleUrl : row.introUrl;
    final sha = middle ? row.middleSha256 : row.introSha256;
    final bytes = middle ? row.middleBytes : row.introBytes;
    if (url == null || sha == null || bytes == null) return null;
    return RemoteClip(url: url, sha256: sha, bytes: bytes);
  }

  /// The tracks a session can ask about: those with their clip on the device, plus, when
  /// [includeFetchable] is set, those whose clip can be downloaded.
  Set<int> playableIds(GameMode mode, {required bool includeFetchable}) => {
        for (final t in tracks)
          if (hasClip(t.id, mode) || (includeFetchable && remoteClip(t.id, mode) != null)) t.id,
      };
}

Future<GameLibrary> loadGameLibrary(AppDb db, Directory base) async {
  final catalog = await db.select(db.catalogTracks).get();
  final clips = await db.select(db.clips).get();
  return GameLibrary.fromRows(catalog, clips, base);
}
