import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';

void main() {
  late AppDb db;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schema version is 2', () {
    expect(db.schemaVersion, 2);
  });

  test('creates all three tables and round-trips a row in each', () async {
    await db.into(db.installedPacks).insert(
          InstalledPacksCompanion.insert(
            slug: 'golden-era',
            version: 3,
            manifestJson: '{"schema":1}',
            installedAt: 1760000000000,
            totalBytes: 319312,
          ),
        );
    await db.into(db.localTracks).insert(
          LocalTracksCompanion.insert(
            packSlug: 'golden-era',
            id: 41,
            titleAm: const Value('የማን ዘፈን'),
            introPath: const Value('golden-era/41-intro.mp3'),
          ),
        );
    await db.into(db.pendingSessions).insert(
          PendingSessionsCompanion.insert(
            id: 'session-1',
            payloadJson: '{}',
            createdAt: 1760000000000,
          ),
        );

    final pack = await db.select(db.installedPacks).getSingle();
    expect(pack.slug, 'golden-era');
    expect(pack.version, 3);

    final track = await db.select(db.localTracks).getSingle();
    expect(track.titleAm, 'የማን ዘፈን');
    expect(track.middlePath, isNull);

    final session = await db.select(db.pendingSessions).getSingle();
    expect(session.attempts, 0);
    expect(session.lastError, isNull);
  });

  test('a track can be stored once per pack', () async {
    Future<void> insertTrack(String pack) => db.into(db.localTracks).insert(
          LocalTracksCompanion.insert(packSlug: pack, id: 41),
        );

    await insertTrack('golden-era');
    await insertTrack('second-pack');
    expect(await db.select(db.localTracks).get(), hasLength(2));
    expect(() => insertTrack('golden-era'), throwsA(anything));
  });
}
