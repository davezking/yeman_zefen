import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/audio/audio_providers.dart';
import 'package:yeman_zefen/core/audio/clip_player.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/game/application/session_controller.dart';
import 'package:yeman_zefen/features/game/application/session_environment.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
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

  static Future<SessionKit> create({int tracks = 30}) async {
    final kit = SessionKit._();
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
    await kit._seed(tracks);
    kit.container = ProviderContainer(
      overrides: [
        appDbProvider.overrideWithValue(kit.db),
        supportDirectoryProvider.overrideWith((ref) async => kit.dir),
        clipPlayerProvider.overrideWithValue(kit.player),
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

  Future<void> _seed(int n) async {
    for (var id = 1; id <= n; id++) {
      await db.into(db.localTracks).insert(
            LocalTracksCompanion.insert(
              packSlug: 't',
              id: id,
              titleAm: Value('ዘፈን $id'),
              titleLatin: Value('Song $id'),
              artistAm: Value('ድምፃዊ ${artistOf(id)}'),
              artistLatin: Value('Artist ${artistOf(id)}'),
              artistId: Value(artistOf(id)),
              generationId: Value(eraOf(id)),
              introPath: Value(introRel(id)),
              middlePath: Value(middleRel(id)),
            ),
          );
      existing
        ..add(p.join(dir.path, introRel(id)))
        ..add(p.join(dir.path, middleRel(id)));
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
