import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/data/catalog_refresher.dart';
import 'package:yeman_zefen/features/packs/data/clip_store.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';

import 'pack_fixtures.dart';

/// Answers `/v1/packs` and the manifests from memory.
class FakePacksApi implements PacksApi {
  final listings = <PackListing>[];
  final manifests = <String, String>{};
  var listFails = false;
  final failingManifests = <String>{};
  final fetched = <String>[];

  void publish(String slug, int version, {int tracks = 3}) {
    final url = 'https://cdn.test/packs/$slug/v$version/manifest.json';
    listings.removeWhere((l) => l.slug == slug);
    listings.add(PackListing(
      slug: slug,
      nameAm: 'a',
      nameEn: 'e',
      version: version,
      manifestUrl: url,
      trackCount: tracks,
      totalBytes: 1,
      publishedAt: 1,
    ));
    manifests[url] = manifestJson(slug: slug, version: version, tracks: tracks);
  }

  @override
  Future<List<PackListing>> listPacks() async {
    if (listFails) throw const PacksApiException('offline');
    return List.of(listings);
  }

  @override
  Future<String> fetchManifestJson(String manifestUrl) async {
    fetched.add(manifestUrl);
    if (failingManifests.contains(manifestUrl)) throw const PacksApiException('boom');
    return manifests[manifestUrl]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDb db;
  late FakePacksApi api;
  late CatalogRefresher refresher;
  var now = 1000000;

  setUp(() {
    now = 1000000;
    db = AppDb(NativeDatabase.memory());
    api = FakePacksApi();
    refresher = CatalogRefresher(
      db: db,
      api: api,
      store: ClipStore(db: db, supportDirectory: () async => throw UnimplementedError()),
      nowMs: () => now,
    );
  });

  tearDown(() => db.close());

  test('reads each published manifest into the catalog', () async {
    api.publish('golden-era', 1, tracks: 3);
    api.publish('starter', 1, tracks: 5);

    await refresher.refresh();

    // Both packs use track ids 1..n, so the catalog holds the union: ids 1..5.
    expect((await db.select(db.catalogTracks).get()).map((t) => t.id).toSet(), {1, 2, 3, 4, 5});
    expect(api.fetched, hasLength(2));
  });

  test('catalog tracks have the clip urls the prefetcher needs', () async {
    api.publish('golden-era', 1);
    await refresher.refresh();

    final track = await (db.select(db.catalogTracks)..where((t) => t.id.equals(1))).getSingle();
    expect(track.introUrl, clipUrl(1, 'intro', 1));
    expect(track.middleUrl, clipUrl(1, 'middle', 1));
    expect(track.introSha256, hasLength(64));
  });

  test('a manifest that was already read at that version is not fetched again; a newer one is', () async {
    api.publish('golden-era', 1);
    await refresher.refresh();
    api.fetched.clear();

    await refresher.refresh();
    expect(api.fetched, isEmpty);

    api.publish('golden-era', 2, tracks: 4);
    await refresher.refresh();
    expect(api.fetched, hasLength(1));
    expect((await db.select(db.catalogTracks).get()), hasLength(4));
    expect((await (db.select(db.catalogTracks)..where((t) => t.id.equals(1))).getSingle()).introUrl, clipUrl(1, 'intro', 2));
  });

  test('refreshing the catalog does not touch the clips on the phone', () async {
    await db.into(db.clips).insert(ClipsCompanion.insert(
          trackId: 1,
          kind: 'intro',
          path: 'starter/1-intro.mp3',
          bytes: 5,
          source: ClipSource.starter,
          lastPlayedAt: 1,
        ));
    api.publish('golden-era', 1);

    await refresher.refresh();

    expect(await db.select(db.clips).get(), hasLength(1));
  });

  group('every 12 hours', () {
    test('refreshes on the first start', () async {
      api.publish('golden-era', 1);
      expect(await refresher.refreshIfDue(), isTrue);
    });

    test('is not due again until 12 hours have passed', () async {
      api.publish('golden-era', 1);
      await refresher.refreshIfDue();

      now += const Duration(hours: 11, minutes: 59).inMilliseconds;
      expect(await refresher.refreshIfDue(), isFalse);

      now += const Duration(minutes: 1).inMilliseconds;
      expect(await refresher.refreshIfDue(), isTrue);
    });

    test('back in front or back online, a refresh older than 15 minutes runs again', () async {
      api.publish('golden-era', 1);
      await refresher.refresh();

      now += const Duration(minutes: 14).inMilliseconds;
      expect(await refresher.refreshIfDue(olderThan: CatalogRefresher.resumeInterval), isFalse);

      api.publish('golden-era', 2, tracks: 5);
      now += const Duration(minutes: 1).inMilliseconds;
      expect(await refresher.refreshIfDue(olderThan: CatalogRefresher.resumeInterval), isTrue);
      expect(await db.select(db.catalogTracks).get(), hasLength(5), reason: 'the new songs are in');
    });
  });

  group('offline or broken', () {
    test('a failed pack list changes nothing, and the next start tries again at once', () async {
      api.listFails = true;
      await refresher.refreshIfDue();

      expect(await db.select(db.catalogTracks).get(), isEmpty);
      api.listFails = false;
      api.publish('golden-era', 1);
      expect(await refresher.refreshIfDue(), isTrue, reason: 'no refresh time was saved');
      expect(await db.select(db.catalogTracks).get(), hasLength(3));
    });

    test('one pack failing does not stop the others, and is retried next time', () async {
      api.publish('golden-era', 1);
      api.publish('starter', 1, tracks: 5);
      api.failingManifests.add(api.listings.first.manifestUrl);

      await refresher.refresh();

      expect((await db.select(db.catalogTracks).get()).length, 5, reason: 'the second pack made it in');
      api.failingManifests.clear();
      api.fetched.clear();
      await refresher.refresh();
      expect(api.fetched, [api.listings.first.manifestUrl], reason: 'only the one that failed');
    });

    test('a manifest that is not the pack it was listed as is ignored', () async {
      api.publish('golden-era', 2);
      api.manifests[api.listings.single.manifestUrl] = manifestJson(slug: 'golden-era', version: 1);

      await refresher.refresh();

      expect(await db.select(db.catalogTracks).get(), isEmpty);
    });

    test('a manifest that cannot be parsed is ignored', () async {
      api.publish('golden-era', 1);
      api.manifests[api.listings.single.manifestUrl] = '{"schema": 2}';

      await refresher.refresh();

      expect(await db.select(db.catalogTracks).get(), isEmpty);
    });
  });
}
