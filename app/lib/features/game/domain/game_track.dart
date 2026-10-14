/// The part of a track the round engine needs. It is built from an installed
/// pack's `local_tracks` row, so the engine knows nothing about storage.
class GameTrack {
  const GameTrack({
    required this.id,
    required this.artistId,
    this.generationId,
  });

  final int id;
  final int artistId;

  /// The track's era, or null when it has none. Eras are numbered in time
  /// order (1 = golden age ... 5 = modern), which is what "adjacent" means.
  final int? generationId;
}
