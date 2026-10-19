import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/application/offline_play.dart';
import 'package:yeman_zefen/features/packs/data/catalog_refresher.dart';
import 'package:yeman_zefen/features/packs/data/clip_store.dart';
import 'package:yeman_zefen/features/packs/data/pack_installer.dart';
import 'package:yeman_zefen/features/packs/data/pack_service.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';
import 'package:yeman_zefen/features/packs/data/packs_providers.dart';
import 'package:yeman_zefen/features/packs/domain/pack_install_progress.dart';
import 'package:yeman_zefen/prototype/models.dart';

import 'catalog_refresher_test.dart' show FakePacksApi;
import 'pack_fixtures.dart';

const _mb = 1024 * 1024;

PackListing _listing({String slug = 'golden-era', int version = 1}) => PackListing(
      slug: slug,
      nameAm: 'ወርቃማ',
      nameEn: 'Golden era',
      version: version,
      manifestUrl: 'u',
      trackCount: 40,
      totalBytes: 12 * _mb,
      publishedAt: 1,
      generationId: 2,
    );

/// Fails each install with the next of [failures] (null succeeds); after them, installs succeed.
class _ScriptedPackService implements PackService {
  _ScriptedPackService([List<PackInstallException?> failures = const []]) : _failures = [...failures];

  final List<PackInstallException?> _failures;
  var installs = 0;

  /// Holds each install open until completed, to cancel one meanwhile.
  Completer<void>? hold;

  /// Holds the next installs one each, before [hold] applies.
  final gates = <Completer<void>>[];

  /// The Wi-Fi rule of each install.
  final wifiOnly = <bool>[];

  @override
  Future<void> install(PackListing listing, {bool Function()? isCancelled, bool wifiOnly = false}) async {
    installs++;
    this.wifiOnly.add(wifiOnly);
    await (gates.isEmpty ? hold : gates.removeAt(0))?.future;
    if (isCancelled?.call() ?? false) {
      throw const PackInstallException('cancelled', failure: PackInstallFailure.cancelled);
    }
    if (_failures.isNotEmpty) {
      final failure = _failures.removeAt(0);
      if (failure != null) throw failure;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('pack downloads', () {
    late AppDb db;

    setUp(() => db = AppDb(NativeDatabase.memory()));
    tearDown(() => db.close());

    ProviderContainer containerWith(PackService service) {
      final container = ProviderContainer(
        overrides: [
          appDbProvider.overrideWithValue(db),
          packServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a finished download leaves no job behind', () async {
      final c = containerWith(_ScriptedPackService());
      await c.read(packDownloadsProvider.notifier).start('golden-era', listings: [_listing()]);
      expect(c.read(packDownloadsProvider), isEmpty);
    });

    test('a checksum failure is downloaded once more by itself before the player sees an error', () async {
      final service = _ScriptedPackService([
        const PackInstallException('mismatch', failure: PackInstallFailure.checksum),
      ]);
      final c = containerWith(service);
      await c.read(packDownloadsProvider.notifier).start('golden-era', listings: [_listing()]);
      expect(service.installs, 2);
      expect(c.read(packDownloadsProvider), isEmpty);
    });

    test('a checksum failure on the second run too is a failed download, with Try again', () async {
      const mismatch = PackInstallException('mismatch', failure: PackInstallFailure.checksum);
      final service = _ScriptedPackService([mismatch, mismatch]);
      final c = containerWith(service);
      await c.read(packDownloadsProvider.notifier).start('golden-era', listings: [_listing()]);
      expect(service.installs, 2);
      final job = c.read(packDownloadsProvider)['golden-era']!;
      expect((job.running, job.problem), (false, PackProblem.downloadFailed));
    });

    test('a full phone says how much more space it needs', () async {
      final c = containerWith(_ScriptedPackService([
        const PackInstallException('full', failure: PackInstallFailure.storageFull, missingBytes: 3 * _mb),
      ]));
      await c.read(packDownloadsProvider.notifier).start('golden-era', listings: [_listing()]);
      final job = c.read(packDownloadsProvider)['golden-era']!;
      expect((job.problem, job.missingBytes), (PackProblem.storageFull, 3 * _mb));
    });

    test('cancelling while the manifest is fetched stops it before the installer starts', () async {
      final service = _ScriptedPackService()..hold = Completer<void>();
      final c = containerWith(service);
      final downloads = c.read(packDownloadsProvider.notifier);
      final run = downloads.start('golden-era', listings: [_listing()]);
      expect(c.read(packDownloadsProvider)['golden-era']!.running, isTrue);

      downloads.cancel('golden-era');
      expect(c.read(packDownloadsProvider), isEmpty);
      service.hold!.complete();
      await run;
      expect(c.read(packDownloadsProvider), isEmpty);
    });

    test('a pack already downloading is not started twice', () async {
      final service = _ScriptedPackService()..hold = Completer<void>();
      final c = containerWith(service);
      final downloads = c.read(packDownloadsProvider.notifier);
      final first = downloads.start('golden-era', listings: [_listing()]);
      await downloads.start('golden-era', listings: [_listing()]);
      expect(service.installs, 1);
      service.hold!.complete();
      await first;
    });

    test('a cancelled run ending late leaves the new download alone', () async {
      final old = Completer<void>();
      final next = Completer<void>();
      final service = _ScriptedPackService()..gates.addAll([old, next]);
      final c = containerWith(service);
      final downloads = c.read(packDownloadsProvider.notifier);

      final first = downloads.start('golden-era', listings: [_listing()]);
      downloads.cancel('golden-era');
      final second = downloads.start('golden-era', listings: [_listing()]);
      expect(c.read(packDownloadsProvider)['golden-era']!.running, isTrue);

      // The cancelled run finds out only now, while the new one is still going.
      old.complete();
      await first;
      expect(c.read(packDownloadsProvider)['golden-era']?.running, isTrue);

      next.complete();
      await second;
      expect(c.read(packDownloadsProvider), isEmpty);
      expect(service.installs, 2);
    });

    test('a pack missing from the list fetches the list again', () async {
      final service = _ScriptedPackService();
      final container = ProviderContainer(
        overrides: [
          appDbProvider.overrideWithValue(db),
          packServiceProvider.overrideWithValue(service),
          packListingsProvider.overrideWith((ref) async => [_listing()]),
        ],
      );
      addTearDown(container.dispose);

      await container.read(packDownloadsProvider.notifier).start('golden-era');
      expect(service.installs, 1);
      expect(container.read(packDownloadsProvider), isEmpty);
    });

    test('a tap while the list is still loading waits for it instead of fetching it again', () async {
      final service = _ScriptedPackService();
      final list = Completer<List<PackListing>>();
      var fetches = 0;
      final container = ProviderContainer(
        overrides: [
          appDbProvider.overrideWithValue(db),
          packServiceProvider.overrideWithValue(service),
          packListingsProvider.overrideWith((ref) {
            fetches++;
            return list.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      // The screen is open and its list is loading.
      final screen = container.listen(packListingsProvider, (_, _) {});
      addTearDown(screen.close);

      final run = container.read(packDownloadsProvider.notifier).start('golden-era');
      list.complete([_listing()]);
      await run;
      expect(fetches, 1);
      expect(service.installs, 1);
    });

    test('a pack the list still does not have fails with Try again, rather than doing nothing', () async {
      final service = _ScriptedPackService();
      final container = ProviderContainer(
        overrides: [
          appDbProvider.overrideWithValue(db),
          packServiceProvider.overrideWithValue(service),
          packListingsProvider.overrideWith((ref) async => throw Exception('server error')),
        ],
      );
      addTearDown(container.dispose);

      await container.read(packDownloadsProvider.notifier).start('golden-era');
      expect(service.installs, 0);
      final job = container.read(packDownloadsProvider)['golden-era']!;
      expect((job.running, job.problem), (false, PackProblem.downloadFailed));
    });

    test('the automatic re-run after a bad file keeps the Wi-Fi rule', () async {
      final service = _ScriptedPackService([
        const PackInstallException('mismatch', failure: PackInstallFailure.checksum),
      ]);
      final c = containerWith(service);
      await c.read(packDownloadsProvider.notifier).start('golden-era', listings: [_listing()], wifiOnly: true);
      expect(service.wifiOnly, [true, true]);
    });
  });

  group('the update badge', () {
    late AppDb db;
    late ProviderContainer container;
    late FakePacksApi api;
    late CatalogRefresher refresher;

    setUp(() {
      db = AppDb(NativeDatabase.memory());
      container = ProviderContainer(overrides: [appDbProvider.overrideWithValue(db)]);
      // Listened to, as the badge is on screen: an unlistened provider is paused.
      container.listen(packUpdateAvailableProvider, (_, _) {});
      api = FakePacksApi();
      refresher = CatalogRefresher(
        db: db,
        api: api,
        store: ClipStore(db: db, supportDirectory: () async => throw UnimplementedError()),
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> installed(String slug, int version) {
      return db.into(db.installedPacks).insertOnConflictUpdate(
            InstalledPacksCompanion.insert(
              slug: slug,
              version: version,
              manifestJson: manifestJson(slug: slug, version: version),
              installedAt: 1,
              totalBytes: 1,
            ),
          );
    }

    /// What the badge follows, once the database's change has reached it.
    Future<Set<String>> updates() async {
      await pumpEventQueue();
      return container.read(packUpdatesProvider).requireValue;
    }

    test('appears when the catalog refresh finds a newer version of an installed pack', () async {
      api.publish('golden-era', 1);
      await refresher.refresh();
      await installed('golden-era', 1);
      expect(await updates(), isEmpty);

      api.publish('golden-era', 2);
      await refresher.refresh();

      expect(await updates(), {'golden-era'});
      expect(container.read(packUpdateAvailableProvider), isTrue);
    });

    test('goes once the update is installed', () async {
      api.publish('golden-era', 2);
      await refresher.refresh();
      await installed('golden-era', 1);
      expect(await updates(), {'golden-era'});

      await installed('golden-era', 2);
      expect(await updates(), isEmpty);
    });

    test('a newer version of a pack that is not installed is no update', () async {
      api.publish('the-90s', 3);
      await refresher.refresh();
      expect(await updates(), isEmpty);
    });
  });

  group('pack rows', () {
    final installed = [
      const InstalledPackInfo(
        slug: 'golden-era',
        version: 1,
        nameAm: 'ወርቃማ',
        nameEn: 'Golden era',
        songCount: 40,
        totalBytes: 10 * _mb,
        generationId: 2,
      ),
    ];

    List<PackItem> rows({
      List<PackListing>? listings,
      Map<String, PackJob> jobs = const {},
      PackInstallProgress? progress,
      Set<String> updates = const {},
    }) {
      return packItems(
        listings: listings,
        installed: installed,
        updates: updates,
        jobs: jobs,
        progress: (_) => progress,
      );
    }

    test('an installed pack with a newer listing offers the update at the listing\'s size', () {
      final row = rows(listings: [_listing(version: 2)]).single;
      expect(row.status, PackStatus.updateAvailable);
      expect((row.sizeMb, row.downloadSizeMb), (10, 12));
    });

    test('offline, the update the catalog knows of still shows', () {
      expect(rows(updates: {'golden-era'}).single.status, PackStatus.updateAvailable);
    });

    test('a download that has not reached the installer yet shows an unmeasured bar', () {
      final row = rows(
        listings: [_listing(slug: 'the-90s')],
        jobs: {'the-90s': const PackJob.running()},
        // The end of an earlier run.
        progress: const PackInstallProgress(slug: 'the-90s', state: PackInstallState.failed),
      ).last;
      expect((row.status, row.progress), (PackStatus.downloading, null));
    });

    test('a failed update stays on the phone with the error', () {
      final row = rows(
        listings: [_listing(version: 2)],
        jobs: {'golden-era': const PackJob.failed(PackProblem.downloadFailed)},
      ).single;
      expect((row.status, row.problem, row.isOnPhone), (PackStatus.failed, PackProblem.downloadFailed, true));
    });

    test('a download running again after a bad file says so', () {
      final row = rows(
        listings: [_listing(slug: 'the-90s')],
        jobs: {'the-90s': const PackJob.running(retryingCorrupt: true)},
      ).last;
      expect((row.status, row.problem), (PackStatus.failed, PackProblem.corrupt));
    });

    test('the starter pack is never listed', () {
      expect(rows(listings: [_listing(slug: 'starter')]).map((r) => r.id), ['golden-era']);
    });
  });
}
