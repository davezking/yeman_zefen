import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/net/network_kind.dart';
import 'package:yeman_zefen/features/game/application/play_setup.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart';
import 'package:yeman_zefen/features/packs/data/clip_providers.dart';
import 'package:yeman_zefen/features/packs/data/packs_providers.dart';

void main() {
  late AppDb db;
  late Directory dir;
  late StreamController<NetworkKind> network;
  late Completer<void> starter;

  ProviderContainer containerFor(NetworkKind first) {
    final c = ProviderContainer(
      overrides: [
        appDbProvider.overrideWithValue(db),
        supportDirectoryProvider.overrideWith((ref) async => dir),
        starterReadyProvider.overrideWith((ref) => starter.future),
        networkKindProvider.overrideWithValue(() async => first),
        networkChangesProvider.overrideWithValue(() => network.stream),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('play_setup_test');
    network = StreamController<NetworkKind>.broadcast();
    starter = Completer<void>();
  });

  tearDown(() async {
    await network.close();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// A catalog track in era 1 with its intro on the phone.
  Future<void> addTrack(int id, {bool onDevice = true, bool fetchable = false}) async {
    await db.into(db.catalogTracks).insert(
          CatalogTracksCompanion.insert(
            id: Value(id),
            artistId: 100 + id,
            generationId: const Value(1),
            introUrl: Value(fetchable ? 'https://cdn.test/$id.mp3' : null),
            introSha256: Value(fetchable ? 'a' * 64 : null),
            introBytes: Value(fetchable ? 10 : null),
            updatedAt: 1,
          ),
        );
    if (onDevice) {
      await db.into(db.clips).insert(
            ClipsCompanion.insert(
              trackId: id,
              kind: 'intro',
              path: 'starter/$id-intro.mp3',
              bytes: 10,
              source: ClipSource.starter,
              lastPlayedAt: 1,
            ),
          );
    }
  }

  test('waits for the starter clips, then counts them', () async {
    final c = containerFor(NetworkKind.none);
    final sub = c.listen(playableSongsProvider(GameMode.intro), (_, _) {});
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(playableSongsProvider(GameMode.intro)).isLoading, isTrue, reason: 'the starter is still registering');

    for (var id = 1; id <= 4; id++) {
      await addTrack(id);
    }
    starter.complete();

    final songs = await c.read(playableSongsProvider(GameMode.intro).future);
    expect(songs.countFor(1), 4);
    expect(songs.disabledEras, isNot(contains(1)));
    expect(songs.tooFew, isFalse);
  });

  test('counts again when clips arrive on the phone', () async {
    starter.complete();
    final c = containerFor(NetworkKind.none);
    final sub = c.listen(playableSongsProvider(GameMode.intro), (_, _) {});
    addTearDown(sub.close);
    expect((await c.read(playableSongsProvider(GameMode.intro).future)).tooFew, isTrue);

    for (var id = 1; id <= 4; id++) {
      await addTrack(id);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect((await c.read(playableSongsProvider(GameMode.intro).future)).countFor(1), 4);
  });

  test('fetchable songs count once the connection comes back', () async {
    starter.complete();
    for (var id = 1; id <= 4; id++) {
      await addTrack(id, onDevice: false, fetchable: true);
    }
    final c = containerFor(NetworkKind.none);
    final sub = c.listen(playableSongsProvider(GameMode.intro), (_, _) {});
    addTearDown(sub.close);
    expect((await c.read(playableSongsProvider(GameMode.intro).future)).countFor(1), 0);

    network.add(NetworkKind.unmetered);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(c.read(currentNetworkProvider).value, NetworkKind.unmetered);
    expect((await c.read(playableSongsProvider(GameMode.intro).future)).countFor(1), 4);
  });
}
