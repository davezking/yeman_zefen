import 'dart:async';
import 'dart:math';


import '../../game/data/game_library.dart';
import '../../game/domain/game_track.dart';
import '../../game/domain/generated_session.dart';
import '../../game/domain/round_generator.dart';
import '../../game/domain/session_config.dart';
import 'clip_downloader.dart';
import 'clip_store.dart';

typedef PrefetchTimer = Timer Function(Duration duration, void Function() callback);

/// What a round needs before it can play.
sealed class PreparedRound {
  const PreparedRound();
}

/// The round to play, whose clip is at [path]. The round can differ from the planned one: see
/// [ClipPrefetcher.prepare].
class RoundReady extends PreparedRound {
  const RoundReady(this.round, this.path);
  final GeneratedRound round;
  final String path;
}

/// No clip arrived: the round is skipped, with no penalty. [fileMissing] says the catalog had
/// the clip on the device but its file was gone, which the session counts as a clip error.
class RoundUnavailable extends PreparedRound {
  const RoundUnavailable({this.fileMissing = false});
  final bool fileMissing;
}

/// Keeps the clips for the next few rounds of a session on the device, and decides what a round
/// plays when its clip is not there yet.
///
/// Only the clip for the session's mode is downloaded, and only for the track the round asks
/// about: the wrong answers are names from the catalog. Every download is checked against the
/// manifest's SHA-256 and registered as a `stream` clip.
///
/// A round never waits when it can be avoided. When its clip is not ready, [prepare] swaps in a
/// track whose clip is already on the device (same era filter as the session, not used in the
/// session yet) and builds new options for it. Only when there is no such track does the round
/// wait for its own download, for at most [waitLimit]; after that it is skipped.
class ClipPrefetcher {
  ClipPrefetcher({
    required this.library,
    required this.config,
    required this.rounds,
    required this.generator,
    required this.downloader,
    required this.store,
    required this.fileExists,
    required this.timer,
    required this.allowDownloads,
    required this.rng,
    this.recentTrackIds = const {},
    this.lookahead = 6,
    this.waitLimit = const Duration(seconds: 10),
    this.maxDownloadAttempts = 2,
  })  : _kind = ClipKind.forMode(config.mode),
        _rounds = List.of(rounds),
        _taken = {for (final r in rounds) r.trackId} {
    for (final t in library.tracks) {
      final path = library.clipPath(t.id, config.mode);
      if (path != null) _onDevice[t.id] = path;
      _tracks[t.id] = t;
    }
    store.sessionStarted();
  }

  final GameLibrary library;
  final SessionConfig config;

  /// The rounds as planned. [roundAt] has them as they are now, after swaps.
  final List<GeneratedRound> rounds;
  final RoundGenerator generator;
  final ClipDownloader downloader;
  final ClipStore store;
  final Future<bool> Function(String path) fileExists;
  final PrefetchTimer timer;

  /// Downloads are allowed: the phone is online and not on mobile data the player ruled out.
  final bool allowDownloads;
  final Random rng;

  /// Tracks played in the last few sessions. A swap takes other tracks first, as the round
  /// generator does, so the same few clips on the phone do not open every session.
  final Set<int> recentTrackIds;

  /// How many rounds have their clip fetched: the one about to play and the next 5.
  final int lookahead;

  /// How long a round waits for its own clip when nothing else can play.
  final Duration waitLimit;

  /// Downloads per clip, including the first. A checksum mismatch costs one.
  final int maxDownloadAttempts;

  final ClipKind _kind;
  final List<GeneratedRound> _rounds;

  /// Tracks planned or played in this session. A swapped-out track is released.
  final Set<int> _taken;
  final _tracks = <int, GameTrack>{};

  /// Absolute paths of the mode's clip for tracks that have one on the device.
  final _onDevice = <int, String>{};
  final _downloads = <int, Future<bool>>{};
  final _closed = Completer<void>();

  GeneratedRound roundAt(int index) => _rounds[index];

  /// Tracks played or planned so far, in round order as they stand.
  List<int> get trackIds => [for (final r in _rounds) r.trackId];

  /// Starts downloads for the rounds from [index] on, up to [lookahead] rounds.
  void prefetchFrom(int index) {
    if (!allowDownloads || _closed.isCompleted) return;
    final end = min(index + lookahead, _rounds.length);
    for (var i = max(index, 0); i < end; i++) {
      final id = _rounds[i].trackId;
      if (_onDevice.containsKey(id) || _downloads.containsKey(id)) continue;
      if (library.remoteClip(id, config.mode) == null) continue;
      _downloads[id] = _download(id);
    }
  }

  /// The path of the clip for round [index] if it is on the device now, without swapping or
  /// waiting. Lets the player load the next clip while this one plays.
  String? readyPath(int index) {
    if (index >= _rounds.length) return null;
    return _onDevice[_rounds[index].trackId];
  }

  /// Gets round [index] ready to play.
  ///
  /// 1. The planned round, when its clip is on the device.
  /// 2. Otherwise a swap: a track whose clip is on the device, in the session's era, not used yet.
  ///    The round keeps its kind of question and gets new options.
  /// 3. Otherwise the round's own download, awaited for up to [waitLimit]. If it fails or is too
  ///    slow, the round is [RoundUnavailable].
  Future<PreparedRound> prepare(int index) async {
    final planned = _rounds[index];
    final own = await _verifiedPath(planned.trackId);
    if (own != null) return RoundReady(planned, own);

    final swapped = await _swapIn(index);
    if (swapped != null) return swapped;

    final missing = RoundUnavailable(fileMissing: library.hasClip(planned.trackId, config.mode));
    if (!allowDownloads || _closed.isCompleted) return missing;
    final id = planned.trackId;
    if (library.remoteClip(id, config.mode) == null && !_downloads.containsKey(id)) return missing;
    final pending = _downloads[id] ??= _download(id);
    final timedOut = Completer<bool>();
    final clock = timer(waitLimit, () {
      if (!timedOut.isCompleted) timedOut.complete(false);
    });
    final ok = await Future.any([pending, timedOut.future, _closed.future.then((_) => false)]);
    clock.cancel();
    if (!ok) return const RoundUnavailable();
    final path = await _verifiedPath(id);
    return path == null ? missing : RoundReady(planned, path);
  }

  /// The clip was played: moves it to the back of the line for eviction.
  Future<void> markPlayed(int trackId) => store.touch(trackId, _kind);

  /// Stops starting downloads, lets the ones running finish, then, once no other session is
  /// running, evicts `stream` clips down to [capBytes], least recently played first. Call it once.
  Future<void> finish({required int capBytes}) async {
    if (_closed.isCompleted) return;
    _closed.complete();
    await Future.wait(_downloads.values.toList());
    await store.sessionEnded(capBytes: capBytes);
  }

  /// The track's clip path if the file is really there. A row whose file is gone is dropped, so
  /// the clip counts as not on the device from then on.
  Future<String?> _verifiedPath(int trackId) async {
    final path = _onDevice[trackId];
    if (path == null) return null;
    if (await fileExists(path)) return path;
    _onDevice.remove(trackId);
    await store.forget(trackId, _kind);
    return null;
  }

  Future<PreparedRound?> _swapIn(int index) async {
    final planned = _rounds[index];
    final era = config.generationId;
    final eligible = [
      for (final id in _onDevice.keys)
        if (!_taken.contains(id) &&
            (era == 0 || _tracks[id]?.generationId == era) &&
            // An era question can only be about a track that has an era.
            (planned.kind != QuestionKind.era || _tracks[id]?.generationId != null))
          id,
    ]..sort(); // a stable order, so the shuffles below are all the randomness there is
    final unseen = [for (final id in eligible) if (!recentTrackIds.contains(id)) id]..shuffle(rng);
    final seen = [for (final id in eligible) if (recentTrackIds.contains(id)) id]..shuffle(rng);
    for (final id in [...unseen, ...seen]) {
      final path = await _verifiedPath(id);
      if (path == null) continue;
      final round = generator.roundFor(_tracks[id]!, planned.kind);
      _taken
        ..remove(planned.trackId)
        ..add(id);
      _rounds[index] = round;
      return RoundReady(round, path);
    }
    return null;
  }

  Future<bool> _download(int trackId) async {
    final remote = library.remoteClip(trackId, config.mode);
    if (remote == null) return false;
    final path = await store.fetchStreamClip(
      trackId: trackId,
      kind: _kind,
      url: remote.url,
      sha256: remote.sha256,
      bytes: remote.bytes,
      downloader: downloader,
      maxAttempts: maxDownloadAttempts,
    );
    if (path == null) return false;
    _onDevice[trackId] = path;
    return true;
  }
}
