import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/net/network_kind.dart';
import 'package:yeman_zefen/features/packs/data/clip_settings.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';
import 'package:yeman_zefen/features/packs/domain/pack_install_progress.dart';

import '../game/presentation/screen_kit.dart';

const _mb = 1024 * 1024;

PackListing _listing(String slug, {int version = 1, String name = 'Golden era'}) => PackListing(
      slug: slug,
      nameAm: 'ወርቃማ',
      nameEn: name,
      version: version,
      manifestUrl: 'https://cdn.test/$slug/v$version/manifest.json',
      trackCount: 40,
      totalBytes: 12 * _mb,
      publishedAt: 1,
      generationId: 2,
    );

Future<String?> _setting(Harness h, String key) async {
  final db = h.container.read(appDbProvider);
  final row = await (db.select(db.appSettings)..where((t) => t.key.equals(key))).getSingleOrNull();
  return row?.value;
}

Future<void> _addClip(Harness h, int trackId, String source, int bytes) {
  final db = h.container.read(appDbProvider);
  return db.into(db.clips).insert(
        ClipsCompanion.insert(
          trackId: trackId,
          kind: 'intro',
          path: '$source/$trackId-intro.mp3',
          bytes: bytes,
          source: source,
          lastPlayedAt: 1,
        ),
      );
}

void main() {
  testWidgets('lists the installed packs and the ones to download, without the starter pack', (tester) async {
    await pumpScreens(
      tester,
      location: '/packs',
      packs: [_listing('golden-era'), _listing('the-90s', name: 'The 90s'), _listing('starter', name: 'Starter')],
      installed: {'golden-era': 1},
    );
    await tester.pumpAndSettle();

    expect(find.text('Golden era'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('The 90s'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Starter'), findsNothing);
  });

  testWidgets('an installed pack with a newer version offers the update', (tester) async {
    await pumpScreens(tester, location: '/packs', packs: [_listing('golden-era', version: 2)], installed: {'golden-era': 1});
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Update · 12 MB'), findsOneWidget);
  });

  group('on mobile data with Wi-Fi only on', () {
    testWidgets('nothing downloads until the player confirms', (tester) async {
      final service = FakePackService();
      await pumpScreens(
        tester,
        location: '/packs',
        packs: [_listing('golden-era')],
        network: NetworkKind.cellular,
        packService: service,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.text('Download on mobile data?'), findsOneWidget);
      expect(find.text('This pack is 12 MB.'), findsOneWidget);

      await tester.tap(find.text('Wait for Wi-Fi'));
      await tester.pumpAndSettle();
      expect(service.installs, isEmpty);

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download now'));
      await tester.pumpAndSettle();
      expect(service.installs.map((l) => l.slug), ['golden-era']);
    });

    testWidgets('with Wi-Fi only off, it downloads without asking, and the choice is saved', (tester) async {
      final service = FakePackService();
      final h = await pumpScreens(
        tester,
        location: '/packs',
        packs: [_listing('golden-era')],
        network: NetworkKind.cellular,
        packService: service,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download packs on Wi-Fi only'));
      await tester.pumpAndSettle();
      expect(await _setting(h, ClipSettings.packWifiOnlyKey), '0');

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.text('Download on mobile data?'), findsNothing);
      expect(service.installs, hasLength(1));
    });
  });

  testWidgets('on Wi-Fi, a download starts straight away', (tester) async {
    final service = FakePackService();
    await pumpScreens(tester, location: '/packs', packs: [_listing('golden-era')], packService: service);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(service.installs, hasLength(1));
  });

  testWidgets('offline, downloads are held back and the screen says why', (tester) async {
    final service = FakePackService();
    await pumpScreens(
      tester,
      location: '/packs',
      packsError: Exception('offline'),
      installed: {'golden-era': 1},
      network: NetworkKind.none,
      packService: service,
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect to the internet to download packs.'), findsOneWidget);
    // The installed pack still shows, by its slug when the list cannot be read.
    expect(find.text('golden-era'), findsOneWidget);
  });

  group('a download in progress', () {
    late Completer<void> hold;
    late StreamController<PackInstallProgress> progress;

    setUp(() {
      hold = Completer<void>();
      progress = StreamController<PackInstallProgress>.broadcast();
    });

    tearDown(() {
      if (!hold.isCompleted) hold.complete();
      progress.close();
    });

    Future<Harness> start(WidgetTester tester) async {
      final h = await pumpScreens(
        tester,
        location: '/packs',
        packs: [_listing('golden-era')],
        packService: FakePackService()..onInstall = (_) => hold.future,
        progress: (_) => progress.stream,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pump();
      progress.add(
        const PackInstallProgress(
          slug: 'golden-era',
          state: PackInstallState.downloading,
          bytesDone: 1,
          bytesTotal: 2,
          filesDone: 40,
          filesTotal: 80,
        ),
      );
      await tester.pump();
      return h;
    }

    testWidgets('shows its progress', (tester) async {
      await start(tester);
      expect(find.textContaining('50% ·'), findsOneWidget);
      expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
    });

    testWidgets('goes on when the player leaves, with the right progress on return', (tester) async {
      final h = await start(tester);
      h.router.go('/settings');
      await tester.pumpAndSettle();
      progress.add(
        const PackInstallProgress(
          slug: 'golden-era',
          state: PackInstallState.downloading,
          bytesDone: 3,
          bytesTotal: 4,
          filesDone: 60,
          filesTotal: 80,
        ),
      );
      await tester.pump();

      h.router.go('/packs');
      await tester.pumpAndSettle();
      expect(find.textContaining('75% ·'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('shows the check once every byte is in', (tester) async {
      await start(tester);
      progress.add(
        const PackInstallProgress(
          slug: 'golden-era',
          state: PackInstallState.verifying,
          bytesDone: 2,
          bytesTotal: 2,
          filesDone: 80,
          filesTotal: 80,
        ),
      );
      await tester.pump();
      expect(find.text('Checking files…'), findsOneWidget);
    });

    testWidgets('can be cancelled', (tester) async {
      await start(tester);
      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Download'), findsOneWidget);
    });
  });

  testWidgets('a failed download says so, with Try again', (tester) async {
    final service = FakePackService()..onInstall = (_) async => throw Exception('connection lost');
    await pumpScreens(tester, location: '/packs', packs: [_listing('golden-era')], packService: service);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(find.text('Download failed. Check your connection and try again.'), findsOneWidget);
    service.onInstall = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(service.installs, hasLength(2));
    expect(find.text('Download failed. Check your connection and try again.'), findsNothing);
  });

  testWidgets('"Download upcoming songs on mobile data" is saved where the prefetcher reads it', (tester) async {
    final h = await pumpScreens(tester, location: '/packs');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download upcoming songs on mobile data'));
    await tester.pumpAndSettle();
    final settings = ClipSettings(h.container.read(appDbProvider));
    expect(await settings.prefetchOnMobile(), isFalse);
  });

  testWidgets('shows the storage the songs use and the cache with its cap', (tester) async {
    final h = await pumpScreens(tester, location: '/packs');
    await _addClip(h, 1, ClipSource.starter, 3 * _mb);
    await _addClip(h, 2, ClipSource.stream, 2 * _mb);
    await _addClip(h, 3, ClipSource.pack, 5 * _mb);
    await tester.pumpAndSettle();

    expect(find.text('Cache 2 of 50 MB'), findsOneWidget);
    expect(find.text('Songs use 10 MB here: built-in 3 MB, packs 5 MB, cache 2 MB.'), findsOneWidget);
    expect(find.text('1 songs · comes with the app'), findsOneWidget);
  });

  testWidgets('Clear cache removes the streamed clips only', (tester) async {
    final h = await pumpScreens(tester, location: '/packs');
    await _addClip(h, 1, ClipSource.starter, _mb);
    await _addClip(h, 2, ClipSource.stream, _mb);
    await _addClip(h, 3, ClipSource.pack, _mb);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear cache'));
    // Clearing deletes files: real I/O, which the test's fake clock does not wait for.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    final db = h.container.read(appDbProvider);
    final left = await db.select(db.clips).get();
    expect(left.map((c) => c.source), unorderedEquals([ClipSource.starter, ClipSource.pack]));
    expect(find.text('Cache 0 of 50 MB'), findsOneWidget);
  });

  testWidgets('Back returns to Settings', (tester) async {
    final h = await pumpScreens(tester, location: '/packs');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(h.location, '/settings');
  });
}
