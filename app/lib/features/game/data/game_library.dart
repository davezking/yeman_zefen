import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/db/app_db.dart';
import '../domain/game_track.dart';
import '../domain/session_config.dart';

/// The installed tracks, as the round engine and the round screen need them:
/// what to ask about, what to call each answer, and where each clip is.
class GameLibrary {
  GameLibrary._(this.tracks, this._rows, this._artistLabels, this._base);

  /// Builds a library from installed `local_tracks` rows. A track in more than
  /// one pack is kept once. Rows without an artist id, which are from before
  /// schema 2, cannot be used and are left out.
  factory GameLibrary.fromRows(Iterable<LocalTrack> rows, Directory base) {
    final byId = <int, LocalTrack>{};
    final artistLabels = <int, String>{};
    for (final row in rows) {
      final artistId = row.artistId;
      if (artistId == null || byId.containsKey(row.id)) continue;
      byId[row.id] = row;
      // The first track that has a name for the artist decides it.
      final label = _label(row.artistAm, row.artistLatin);
      if (label != null) artistLabels.putIfAbsent(artistId, () => label);
    }
    return GameLibrary._(
      [
        for (final row in byId.values)
          GameTrack(id: row.id, artistId: row.artistId!, generationId: row.generationId),
      ],
      byId,
      artistLabels,
      base,
    );
  }

  final List<GameTrack> tracks;
  final Map<int, LocalTrack> _rows;
  final Map<int, String> _artistLabels;
  final Directory _base;

  bool get isEmpty => tracks.isEmpty;

  /// The eras that have at least one track.
  Set<int> get eras => {
        for (final t in tracks)
          if (t.generationId != null) t.generationId!,
      };

  String trackLabel(int trackId) {
    final row = _rows[trackId];
    return (row == null ? null : _label(row.titleAm, row.titleLatin)) ?? 'Track $trackId';
  }

  String artistLabel(int artistId) => _artistLabels[artistId] ?? 'Artist $artistId';

  /// The absolute path of the clip for [mode], or null when the track has none.
  String? clipPath(int trackId, GameMode mode) {
    final row = _rows[trackId];
    final relative = mode == GameMode.middle ? row?.middlePath : row?.introPath;
    return relative == null ? null : p.join(_base.path, relative);
  }

  /// Amharic first, with the Latin spelling under it when it differs.
  static String? _label(String? am, String? latin) {
    final a = am?.trim() ?? '';
    final l = latin?.trim() ?? '';
    if (a.isEmpty && l.isEmpty) return null;
    if (a.isEmpty) return l;
    if (l.isEmpty || l == a) return a;
    return '$a\n$l';
  }
}

Future<GameLibrary> loadGameLibrary(AppDb db, Directory base) async {
  final rows = await db.select(db.localTracks).get();
  return GameLibrary.fromRows(rows, base);
}
