import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/net/network_kind.dart';
import 'package:yeman_zefen/features/game/application/session_state.dart';
import 'package:yeman_zefen/features/game/data/session_store.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/packs/data/clip_settings.dart';
import 'package:yeman_zefen/features/packs/data/clip_store.dart';
import 'package:yeman_zefen/features/packs/data/starter_pack.dart';

import '../../packs/starter_fixtures.dart';
import 'session_kit.dart';

// Easy: a 15 s answer window, so the 10 s wait for a clip is the only 10 s timer.
const easy = SessionConfig(mode: GameMode.intro, difficulty: Difficulty.easy, questions: QuestionMix.song);
const waitLimit = Duration(seconds: 10);

void main() {
  late SessionKit kit;

  tearDown(() async {
    kit.downloader.release();
    await kit.dispose();
  });

  Future<List<int>> savedTrackIds() async {
    final row = await kit.db.select(kit.db.pendingSessions).getSingle();
    final rounds = (jsonDecode(row.payloadJson) as Map<String, dynamic>)['rounds'] as List<dynamic>;
    return [for (final r in rounds) (r as Map<String, dynamic>)['trackId'] as int];
  }

  /// Plays every round correctly and returns the tracks whose clips were playing, in order.
  Future<List<int>> playAndRecord() async {
    final played = <int>[];
    await kit.playAll(pick: () {
      played.add(kit.playingTrackId());
      return kit.correctOption();
    });
    return played;
  }

  Set<int> waitTimers() => {
        for (var i = 0; i < kit.timers.length; i++)
          if (kit.timers[i].duration == waitLimit) i,
      };

  test('a first launch with no network plays a full session from the starter clips', () async {
    kit = await SessionKit.create(tracks: 0);
    // What the app does on its first start: copy the bundled clips and register them.
    final registered = await StarterPack(
      db: kit.db,
      store: ClipStore(db: kit.db, supportDirectory: () async => kit.dir),
      supportDirectory: () async => kit.dir,
      bundle: starterBundle(tracks: 12),
    ).registerIfChanged();
    expect(registered, 12);
    for (final c in await kit.db.select(kit.db.clips).get()) {
      kit.existing.add(p.join(kit.dir.path, c.path));
    }
    expect(kit.offline, isTrue);

    kit.start(easy);
    final played = await playAndRecord();

    expect(kit.state.phase, SessionPhase.finished);
    expect(kit.state.summary!.rounds, hasLength(10));
    expect(kit.state.summary!.skipped, 0);
    // The results name each song that played, for artist questions too.
    expect(kit.state.summary!.rounds.where((r) => r.trackName.isEmpty), isEmpty);
    expect(played.toSet(), hasLength(10));
    expect(kit.downloader.calls, isEmpty, reason: 'offline: nothing is fetched');
    expect(waitTimers(), isEmpty);
    expect(await savedTrackIds(), played);
  });

  test('a first launch also plays artist questions and the middle clip from starter clips', () async {
    kit = await SessionKit.create(tracks: 0);
    await StarterPack(
      db: kit.db,
      store: ClipStore(db: kit.db, supportDirectory: () async => kit.dir),
      supportDirectory: () async => kit.dir,
      bundle: starterBundle(tracks: 12),
    ).registerIfChanged();
    for (final c in await kit.db.select(kit.db.clips).get()) {
      kit.existing.add(p.join(kit.dir.path, c.path));
    }

    kit.start(const SessionConfig(mode: GameMode.middle, difficulty: Difficulty.easy, rounds: 8));
    // Starter tracks have their own artists: ids 101-106.
    await kit.playAll(pick: () {
      final id = kit.playingTrackId();
      return kit.state.round!.kind == QuestionKind.artist ? 101 + id % 6 : id;
    });

    expect(kit.state.phase, SessionPhase.finished);
    expect(kit.state.summary!.rounds, hasLength(8));
    expect(kit.voices.expand((v) => v.loads).every((l) => l.$1.contains('-middle.mp3')), isTrue);
  });

  group('online, with clips still downloading', () {
    test('a slow downloader causes swaps, not waits, when on-device tracks exist for the era', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 20; i++) i});
      kit.offline = false;
      kit.downloader.hold = true; // nothing arrives during the session

      kit.start(easy);
      final played = await playAndRecord();

      expect(kit.state.phase, SessionPhase.finished);
      expect(kit.state.summary!.rounds, hasLength(10));
      expect(kit.state.summary!.skipped, 0);
      expect(played.every((id) => id >= 1 && id <= 20), isTrue, reason: 'only clips already on the phone played');
      expect(played.toSet(), hasLength(10), reason: 'no track twice in a session');
      expect(waitTimers(), isEmpty, reason: 'no round waited for a download');
      expect(kit.downloader.calls, isNotEmpty, reason: 'the next rounds were still being fetched');
      expect(await savedTrackIds(), played, reason: 'the session lists what was played, swaps included');
    });

    test('a swap takes tracks the last sessions did not play', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 20; i++) i});
      kit.offline = false;
      kit.downloader.hold = true;
      // The last session played tracks 1-10.
      await kit.db.into(kit.db.recentSessions).insert(
            RecentSessionsCompanion.insert(
              sessionId: 'earlier',
              playedAt: 1,
              trackIdsJson: jsonEncode([for (var i = 1; i <= 10; i++) i]),
            ),
          );

      kit.start(easy);
      final played = await playAndRecord();

      expect(played, hasLength(10));
      expect(played.every((id) => id > 10), isTrue, reason: 'no track from the last session came back');
    });

    test('a swapped round gets options for the new track, with distinct artists for an artist question', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 20; i++) i});
      kit.offline = false;
      kit.downloader.hold = true;

      kit.start(const SessionConfig(mode: GameMode.intro, difficulty: Difficulty.easy, questions: QuestionMix.artist));
      final played = await playAndRecord();

      final row = await kit.db.select(kit.db.pendingSessions).getSingle();
      final rounds = ((jsonDecode(row.payloadJson) as Map<String, dynamic>)['rounds'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(rounds, hasLength(10));
      for (var i = 0; i < rounds.length; i++) {
        final options = (rounds[i]['optionIds'] as List<dynamic>).cast<int>();
        expect(options.toSet(), hasLength(4), reason: 'four different artists');
        expect(options, contains(SessionKit.artistOf(played[i])));
        expect(rounds[i]['chosenId'], SessionKit.artistOf(played[i]));
      }
    });

    test('only the clip the mode needs is fetched, for the next rounds only', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 20; i++) i});
      kit.offline = false;
      kit.downloader.hold = true;

      kit.start(easy);
      await kit.untilRound(1, RoundPhase.answering);

      expect(kit.downloader.calls.every((u) => u.endsWith('-intro.mp3')), isTrue);
      expect(kit.downloader.calls.length, lessThanOrEqualTo(6), reason: 'the round about to play and the next 5');
    });

    test('downloaded clips are checked and kept as stream clips', () async {
      kit = await SessionKit.create(onDevice: {1, 2, 3, 4, 5, 6});
      kit.offline = false;

      kit.start(easy);
      await playAndRecord();
      await kit.until(
        () => kit.downloader.calls.isNotEmpty,
        what: 'a download',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final stream = await (kit.db.select(kit.db.clips)..where((c) => c.source.equals(ClipSource.stream))).get();
      expect(stream, isNotEmpty);
      for (final c in stream) {
        expect(c.kind, 'intro');
        expect(c.path, ClipStore.streamPath(c.trackId, ClipKind.intro));
      }
    });

    test('a download that returns the wrong bytes is not kept, and the round is skipped', () async {
      // Era 2 (odd tracks) has nothing on the phone, and the CDN serves damaged bytes for all of it.
      kit = await SessionKit.create(onDevice: {for (var i = 2; i <= 30; i += 2) i});
      kit.offline = false;
      for (var id = 1; id <= 30; id += 2) {
        kit.downloader.corrupt.add(SessionKit.clipUrl(id, 'intro'));
      }

      kit.start(const SessionConfig(mode: GameMode.intro, difficulty: Difficulty.easy, generationId: 2, questions: QuestionMix.song, rounds: 3));
      await kit.untilPhase(SessionPhase.failed);

      expect(await (kit.db.select(kit.db.clips)..where((c) => c.source.equals(ClipSource.stream))).get(), isEmpty);
      expect(kit.downloader.calls.length, greaterThan(3), reason: 'each clip was fetched again once');
      expect(kit.dir.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('stream')), isEmpty);
      expect(await SessionStore(kit.db).clipErrorCount(), 0);
    });
  });

  group('an era with no clips on the phone', () {
    // Era 2 is the odd tracks. Only the even tracks (era 1) are on the phone.
    Future<void> setUpEraWithoutClips() async {
      kit = await SessionKit.create(onDevice: {for (var i = 2; i <= 30; i += 2) i});
      kit.offline = false;
    }

    const era2 = SessionConfig(mode: GameMode.intro, difficulty: Difficulty.easy, generationId: 2, questions: QuestionMix.song, rounds: 3);

    test('waits for the download, then skips the round after 10 s, without penalty', () async {
      await setUpEraWithoutClips();
      kit.downloader.hold = true;

      kit.start(era2);
      await kit.untilRound(1, RoundPhase.loading);
      await kit.until(() => waitTimers().isNotEmpty, what: 'the wait for round 1');
      expect(kit.state.round!.phase, RoundPhase.loading, reason: 'the "next song loading" state shows while it waits');

      kit.timers[waitTimers().first].fire();
      // The other rounds' clips arrive.
      kit.downloader.release();
      await kit.playAll(pick: kit.correctOption);

      final summary = kit.state.summary!;
      expect(kit.state.phase, SessionPhase.finished);
      expect(summary.skipped, 1);
      expect(summary.rounds, hasLength(2));
      expect(summary.rounds.every((r) => r.points > 0), isTrue, reason: 'no points taken for the skipped round');
      expect(await SessionStore(kit.db).clipErrorCount(), 0, reason: 'a late download is not a clip error');
      expect(await savedTrackIds(), hasLength(2));
    });

    test('a round whose download arrives in time plays, and nothing is skipped', () async {
      await setUpEraWithoutClips();
      kit.downloader.hold = true;

      kit.start(era2);
      await kit.until(() => waitTimers().isNotEmpty, what: 'the wait for round 1');
      kit.downloader.release(); // within the 10 s
      await kit.playAll(pick: kit.correctOption);

      expect(kit.state.summary!.rounds, hasLength(3));
      expect(kit.state.summary!.skipped, 0);
      expect(kit.timers[waitTimers().first].isActive, isFalse, reason: 'the wait timer was cancelled');
    });

    test('a failed download skips the round at once, without penalty', () async {
      await setUpEraWithoutClips();
      for (var id = 1; id <= 30; id += 2) {
        kit.downloader.failing.add(SessionKit.clipUrl(id, 'intro'));
      }

      kit.start(era2);
      await kit.untilPhase(SessionPhase.failed);

      expect(kit.state.error?.problem, SessionProblem.clipsFailed, reason: 'no round could be played at all');
      expect(await SessionStore(kit.db).clipErrorCount(), 0);
      expect(await kit.db.select(kit.db.pendingSessions).get(), isEmpty);
    });
  });

  group('mobile data', () {
    test('the data saver on cellular plays only clips already on the phone', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 12; i++) i});
      kit.offline = false;
      kit.network = NetworkKind.cellular;
      await ClipSettings(kit.db).setPrefetchOnMobile(false);

      kit.start(easy);
      final played = await playAndRecord();

      expect(played.every((id) => id <= 12), isTrue);
      expect(played.toSet(), hasLength(10));
      expect(kit.downloader.calls, isEmpty);
      expect(waitTimers(), isEmpty);
      // The phone is online, so the payload says so.
      final row = await kit.db.select(kit.db.pendingSessions).getSingle();
      expect((jsonDecode(row.payloadJson) as Map<String, dynamic>)['offline'], isFalse);
    });

    test('with the data saver off (the default), cellular downloads like Wi-Fi', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 12; i++) i});
      kit.offline = false;
      kit.network = NetworkKind.cellular;
      kit.downloader.hold = true;

      kit.start(easy);
      await kit.untilRound(1, RoundPhase.answering);

      expect(kit.downloader.calls, isNotEmpty);
    });

    test('Wi-Fi downloads even with the data saver on', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 12; i++) i});
      kit.offline = false;
      kit.network = NetworkKind.unmetered;
      await ClipSettings(kit.db).setPrefetchOnMobile(false);
      kit.downloader.hold = true;

      kit.start(easy);
      await kit.untilRound(1, RoundPhase.answering);

      expect(kit.downloader.calls, isNotEmpty);
    });
  });

  group('the clip cache', () {
    test('trims stream clips after a session and leaves pack clips alone', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 30; i++) i});
      final store = ClipStore(db: kit.db, supportDirectory: () async => kit.dir);
      // 60 MB of old prefetched clips for tracks that also have a pack clip on the phone.
      for (var id = 101; id <= 103; id++) {
        await kit.db.into(kit.db.clips).insert(
              ClipsCompanion.insert(
                trackId: id,
                kind: 'intro',
                path: ClipStore.streamPath(id, ClipKind.intro),
                bytes: 20 * 1024 * 1024,
                source: ClipSource.stream,
                lastPlayedAt: id,
              ),
            );
      }
      final packBefore = await (kit.db.select(kit.db.clips)..where((c) => c.source.equals(ClipSource.pack))).get();

      kit.start(easy);
      await playAndRecord();
      await kit.until(() => false, what: 'never').timeout(const Duration(milliseconds: 300), onTimeout: () {});

      final usage = await store.usage();
      expect(usage.streamBytes, lessThanOrEqualTo(ClipStore.defaultStreamCacheCapBytes));
      final stream = await (kit.db.select(kit.db.clips)..where((c) => c.source.equals(ClipSource.stream))).get();
      expect(stream.map((c) => c.trackId), isNot(contains(101)), reason: 'the least recently played went first');
      final packAfter = await (kit.db.select(kit.db.clips)..where((c) => c.source.equals(ClipSource.pack))).get();
      expect(packAfter.length, packBefore.length);
    });

    test('a clip that was played is moved to the back of the eviction line', () async {
      kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 30; i++) i});

      kit.start(easy);
      final played = await playAndRecord();

      final rows = await kit.db.select(kit.db.clips).get();
      final touched = rows.where((c) => c.kind == 'intro' && played.contains(c.trackId)).map((c) => c.lastPlayedAt);
      final untouched = rows.where((c) => c.kind == 'intro' && !played.contains(c.trackId)).map((c) => c.lastPlayedAt);
      expect(touched.every((t) => t > 1), isTrue);
      expect(untouched.every((t) => t == 1), isTrue);
    });
  });

  test('a clip file that vanished from the phone is dropped from the clip store', () async {
    kit = await SessionKit.create(onDevice: {for (var i = 1; i <= 30; i++) i});
    kit.existing.remove(kit.clipPath(8));

    kit.start(const SessionConfig(mode: GameMode.intro, difficulty: Difficulty.easy, generationId: 1, questions: QuestionMix.song, rounds: 15));
    await kit.playAll(pick: kit.correctOption);

    final left = await (kit.db.select(kit.db.clips)..where((c) => c.trackId.equals(8))..where((c) => c.kind.equals('intro'))).get();
    expect(left, isEmpty, reason: 'the row is gone, so the clip counts as not on the phone');
    expect(await SessionStore(kit.db).clipErrorCount(), 1);
  });
}
