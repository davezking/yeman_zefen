import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/audio/audio_providers.dart';
import 'package:yeman_zefen/core/audio/clip_player.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/net/network_kind.dart';
import 'package:yeman_zefen/features/game/application/session_controller.dart';
import 'package:yeman_zefen/features/game/application/session_environment.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/packs/data/clip_downloader.dart';
import 'package:yeman_zefen/features/packs/data/clip_providers.dart';
import 'package:yeman_zefen/features/packs/data/packs_providers.dart';

import '../../../core/audio/fake_clip_voice.dart';

class FakeTimer implements Timer {
  FakeTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  var cancelled = false;
  var fired = false;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;

  @override
  void cancel() => cancelled = true;

  void fire() {
    if (!isActive) return;
    fired = true;
    callback();
  }
}

/// Serves the kit's clips. Each download can be held until a test lets it go, or made to fail.
class KitDownloader implements ClipDownloader {
  KitDownloader(this.kit);

  final SessionKit kit;

  /// Every url asked for, in order.
  final calls = <String>[];

  /// Urls whose download fails.
  final failing = <String>{};

  /// Urls that are served with the wrong bytes, like a damaged transfer.
  final corrupt = <String>{};

  /// Downloads wait for [release] when set. Tests release them one by one or all at once.
  bool hold = false;
  final _held = <Completer<void>>[];

  void release() {
    for (final c in _held) {
      if (!c.isCompleted) c.complete();
    }
    _held.clear();
    hold = false;
  }

  @override
  Future<void> download({
    required String url,
    required String relativePath,
    required void Function(double fraction) onProgress,
  }) async {
    calls.add(url);
    if (hold) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (failing.contains(url)) throw const ClipDownloadException('connection lost');
    final id = int.parse(url.split('/').last.split('-').first);
    final kind = url.contains('-middle') ? 'middle' : 'intro';
    final file = File(p.join(kit.dir.path, relativePath));
    await file.parent.create(recursive: true);
    final body = SessionKit.clipBody(id, kind);
    await file.writeAsBytes(corrupt.contains(url) ? [...body, 0] : body);
    kit.existing.add(file.path);
    onProgress(1);
  }
}

/// A session flow with nothing real in it: a manual clock and timers, fake audio
/// voices, a real in-memory database and a temp folder for clip files.
class SessionKit {
  SessionKit._();

  late final AppDb db;
  late final Directory dir;
  late final ClipPlayer player;
  late final ProviderContainer container;

  final voices = <FakeClipVoice>[];
  final interruptions = StreamController<void>.broadcast();
  final timers = <FakeTimer>[];

  var clockMs = 100000;
  var offline = true;
  var seed = 1;
  var idCounter = 0;

  /// Clip files that exist. Tests remove paths to make clips go missing.
  final existing = <String>{};

  static const feedback = Duration(seconds: 1);

  late final KitDownloader downloader;

  /// What the phone is connected to. Null follows [offline].
  NetworkKind? network;

  /// Tracks 1..[tracks] are in the catalog. Those in [onDevice] (default: all) have both clips on
  /// the device, as `pack` clips; the others can only be fetched.
  static Future<SessionKit> create({int tracks = 30, Set<int>? onDevice}) async {
    final kit = SessionKit._();
    kit.downloader = KitDownloader(kit);
    kit.dir = Directory.systemTemp.createTempSync('session_kit');
    kit.db = AppDb(NativeDatabase.memory());
    kit.player = ClipPlayer(
      voiceFactory: () {
        final v = FakeClipVoice();
        kit.voices.add(v);
        return v;
      },
      interruptions: kit.interruptions.stream,
    );
    await kit._seed(tracks, onDevice ?? {for (var i = 1; i <= tracks; i++) i});
    kit.container = ProviderContainer(
      overrides: [
        appDbProvider.overrideWithValue(kit.db),
        supportDirectoryProvider.overrideWith((ref) async => kit.dir),
        clipPlayerProvider.overrideWithValue(kit.player),
        clipDownloaderProvider.overrideWithValue(kit.downloader),
        starterReadyProvider.overrideWith((ref) async {}),
        sessionEnvironmentProvider.overrideWithValue(
          SessionEnvironment(
            monotonicMs: () => kit.clockMs,
            epochMs: () => 1760000000000 + kit.clockMs,
            timer: (d, cb) {
              final t = FakeTimer(d, cb);
              kit.timers.add(t);
              return t;
            },
            fileExists: (path) async => kit.existing.contains(path),
            newId: () => 'session-${++kit.idCounter}',
            isOffline: () async => kit.offline,
            networkProbe: () async => kit.network ?? (kit.offline ? NetworkKind.none : NetworkKind.unmetered),
            rng: () => Random(kit.seed),
            feedbackDuration: feedback,
          ),
        ),
      ],
    );
    return kit;
  }

  /// Tracks 1..n. Track i has artist 100 + i % 8 and is in era 1 + i % 2.
  static int artistOf(int trackId) => 100 + trackId % 8;
  static int eraOf(int trackId) => 1 + trackId % 2;
  static String introRel(int id) => 'packs/t/v1/$id-intro.mp3';
  static String middleRel(int id) => 'packs/t/v1/$id-middle.mp3';

  static List<int> clipBody(int id, String kind) => utf8.encode('clip:$id:$kind');

  static String clipUrl(int id, String kind) => 'https://cdn.test/clips/$id-$kind.mp3';

  Future<void> _seed(int n, Set<int> onDevice) async {
    for (var id = 1; id <= n; id++) {
      final intro = clipBody(id, 'intro');
      final middle = clipBody(id, 'middle');
      await db.into(db.catalogTracks).insert(
            CatalogTracksCompanion.insert(
              id: Value(id),
              titleAm: Value('ዘፈን $id'),
              titleLatin: Value('Song $id'),
              artistAm: Value('ድምፃዊ ${artistOf(id)}'),
              artistLatin: Value('Artist ${artistOf(id)}'),
              artistId: artistOf(id),
              generationId: Value(eraOf(id)),
              introUrl: Value(clipUrl(id, 'intro')),
              introSha256: Value(sha256.convert(intro).toString()),
              introBytes: Value(intro.length),
              middleUrl: Value(clipUrl(id, 'middle')),
              middleSha256: Value(sha256.convert(middle).toString()),
              middleBytes: Value(middle.length),
              updatedAt: 1,
            ),
          );
      if (!onDevice.contains(id)) continue;
      for (final (kind, rel) in [('intro', introRel(id)), ('middle', middleRel(id))]) {
        await db.into(db.clips).insert(
              ClipsCompanion.insert(
                trackId: id,
                kind: kind,
                path: rel,
                bytes: 100,
                source: ClipSource.pack,
                lastPlayedAt: 1,
              ),
            );
        existing.add(p.join(dir.path, rel));
      }
    }
  }

  String clipPath(int trackId, {bool middle = false}) =>
      p.join(dir.path, middle ? middleRel(trackId) : introRel(trackId));

  SessionController get controller => container.read(sessionControllerProvider.notifier);
  SessionState get state => container.read(sessionControllerProvider);

  Future<void> until(bool Function() test, {String what = 'condition'}) async {
    for (var i = 0; i < 1000; i++) {
      if (test()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    throw StateError('timed out waiting for $what; state is ${state.phase} ${state.round?.phase}');
  }

  Future<RoundView> untilRound(int number, RoundPhase phase, {int? attempt}) async {
    await until(
      () => state.round?.number == number && state.round?.phase == phase && (attempt == null || state.round?.attempt == attempt),
      what: 'round $number $phase',
    );
    return state.round!;
  }

  Future<void> untilPhase(SessionPhase phase) => until(() => state.phase == phase, what: 'session $phase');

  /// The track whose clip is playing now, read from the file the fake voice loaded.
  int playingTrackId() {
    final voice = voices.firstWhere((v) => v.playing);
    final name = p.basename(voice.loads.last.$1);
    return int.parse(name.split('-').first);
  }

  /// The correct option id for the round on screen. Song questions: the track.
  /// Artist questions: its artist.
  int correctOption() {
    final id = playingTrackId();
    return state.round!.kind == QuestionKind.artist ? artistOf(id) : id;
  }

  int wrongOption() {
    final correct = correctOption();
    return state.round!.options.firstWhere((o) => o.id != correct).id;
  }

  /// Ends the feedback pause of the round on screen.
  void endFeedback() {
    timers.lastWhere((t) => t.isActive && t.duration == feedback).fire();
  }

  /// Fires the answer window of the round on screen.
  void endWindow(int windowMs) {
    timers.lastWhere((t) => t.isActive && t.duration == Duration(milliseconds: windowMs)).fire();
  }

  void start(SessionConfig config) => unawaited(controller.start(config));

  /// Answers every round that gets played, then returns when the session has
  /// finished or failed. [pick] chooses an option from the round on screen.
  /// Skipped rounds keep their number, so numbers can jump.
  Future<void> playAll({required int Function() pick, int responseMs = 2500}) async {
    var last = 0;
    while (true) {
      await until(
        () =>
            state.phase == SessionPhase.finished ||
            state.phase == SessionPhase.failed ||
            (state.round?.phase == RoundPhase.answering && state.round!.number > last),
        what: 'the next round',
      );
      if (state.phase == SessionPhase.finished || state.phase == SessionPhase.failed) return;
      final number = state.round!.number;
      last = number;
      clockMs += responseMs;
      controller.answer(pick());
      await untilRound(number, RoundPhase.feedback);
      endFeedback();
    }
  }

  Future<void> dispose() async {
    container.dispose();
    await player.dispose();
    await interruptions.close();
    await db.close();
    dir.deleteSync(recursive: true);
  }
}
