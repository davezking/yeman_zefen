import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/db/app_db.dart';
import '../../../core/l10n/display_name.dart';
import '../domain/game_track.dart';
import '../domain/session_config.dart';

/// The installed tracks, as the round engine and the round screen need them:
/// what to ask about, what to call each answer, and where each clip is.
class GameLibrary {
  GameLibrary._(this.tracks, this._rows, this._artistNames, this._base);

  /// Builds a library from installed `local_tracks` rows. A track in more than
  /// one pack is kept once. Rows without an artist id, which are from before
  /// schema 2, cannot be used and are left out.
  factory GameLibrary.fromRows(Iterable<LocalTrack> rows, Directory base) {
    final byId = <int, LocalTrack>{};
    final artistNames = <int, DisplayName>{};
    for (final row in rows) {
      final artistId = row.artistId;
      if (artistId == null || byId.containsKey(row.id)) continue;
      byId[row.id] = row;
      // The first track that has a name for the artist decides it.
      final name = DisplayName.of(row.artistAm, row.artistLatin);
      if (!name.isEmpty) artistNames.putIfAbsent(artistId, () => name);
    }
    return GameLibrary._(
      [
        for (final row in byId.values)
          GameTrack(id: row.id, artistId: row.artistId!, generationId: row.generationId),
      ],
      byId,
      artistNames,
      base,
    );
  }

  final List<GameTrack> tracks;
  final Map<int, LocalTrack> _rows;
  final Map<int, DisplayName> _artistNames;
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

  /// The absolute path of the clip for [mode], or null when the track has none.
  String? clipPath(int trackId, GameMode mode) {
    final row = _rows[trackId];
    final relative = mode == GameMode.middle ? row?.middlePath : row?.introPath;
    return relative == null ? null : p.join(_base.path, relative);
  }
}

Future<GameLibrary> loadGameLibrary(AppDb db, Directory base) async {
  final rows = await db.select(db.localTracks).get();
  return GameLibrary.fromRows(rows, base);
}
