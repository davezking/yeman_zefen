import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/packs/data/pack_installer.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';
import 'package:yeman_zefen/features/packs/domain/pack_install_progress.dart';

import '../game/presentation/screen_kit.dart';

const golden = PackListing(
  slug: 'golden-era',
  nameAm: 'ወርቃማ ዘመን',
  nameEn: 'Golden era',
  version: 3,
  manifestUrl: 'https://cdn.test/packs/golden-era/v3/manifest.json',
  trackCount: 120,
  totalBytes: 19 * 1024 * 1024,
  publishedAt: 1760000000000,
);

const modern = PackListing(
  slug: 'modern',
  nameAm: 'Modern',
  nameEn: 'Modern',
  version: 1,
  manifestUrl: 'https://cdn.test/packs/modern/v1/manifest.json',
  trackCount: 40,
  totalBytes: 6 * 1024 * 1024,
  publishedAt: 1760000000000,
);

void main() {
  /// The install button of the pack whose title contains [name].
  FilledButton buttonIn(WidgetTester tester, String name) {
    final tile = find.ancestor(of: find.textContaining(name), matching: find.byType(ListTile));
    return tester.widget<FilledButton>(find.descendant(of: tile, matching: find.byType(FilledButton)));
  }

  testWidgets('lists each pack with its songs, size and version', (tester) async {
    await pumpScreens(tester, location: '/packs', packs: [golden, modern]);

    expect(find.text('Golden era'), findsOneWidget, reason: 'English shows the Latin name only');
    expect(find.textContaining('ወርቃማ ዘመን'), findsNothing);
    expect(find.text('120 songs · 19.0 MB · v3'), findsOneWidget);
    expect(find.text('40 songs · 6.0 MB · v1'), findsOneWidget);
  });

  testWidgets('offers Install, Update or nothing depending on what is installed', (tester) async {
    await pumpScreens(
      tester,
      location: '/packs',
      packs: [golden, modern, const PackListing(
        slug: 'eighties', nameAm: '80s', nameEn: '80s', version: 2, manifestUrl: 'u', trackCount: 10, totalBytes: 1024, publishedAt: 1,
      )],
      installed: {'golden-era': 2, 'modern': 1},
    );

    expect(find.text('Update'), findsOneWidget, reason: 'golden era: installed 2, listed 3');
    expect(find.text('Downloaded'), findsOneWidget, reason: 'modern: up to date');
    expect(find.text('Download'), findsOneWidget, reason: 'the 80s pack: not installed');
    expect(find.textContaining('installed v2'), findsOneWidget);
    expect(buttonIn(tester, 'Modern').onPressed, isNull, reason: 'an up to date pack cannot be installed again');
  });

  testWidgets('tapping Install installs that pack', (tester) async {
    final service = FakePackService();
    await pumpScreens(tester, location: '/packs', packs: [golden], packService: service);

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(service.installs.map((p) => p.slug), ['golden-era']);
  });

  testWidgets('shows progress while installing and stops when it is done', (tester) async {
    final progress = StreamController<PackInstallProgress>();
    final release = Completer<void>();
    final service = FakePackService()..onInstall = (_) => release.future;
    await pumpScreens(
      tester,
      location: '/packs',
      packs: [golden],
      packService: service,
      progress: (_) => progress.stream,
    );
    // Not awaited: the done event needs the widget tester's clock, so awaiting it would hang.
    addTearDown(() => unawaited(progress.close()));

    await tester.tap(find.text('Download'));
    await tester.pump();
    progress.add(const PackInstallProgress(
      slug: 'golden-era', state: PackInstallState.downloading,
      bytesDone: 5 * 1024 * 1024, bytesTotal: 20 * 1024 * 1024, filesDone: 30, filesTotal: 240,
    ));
    await tester.pump();

    expect(find.text('Installing'), findsOneWidget);
    expect(find.text('Downloading 30/240 files'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byKey(const Key('install-progress'))).value, closeTo(0.25, 0.001));
    expect(buttonIn(tester, 'Golden era').onPressed, isNull, reason: 'no second install while one runs');

    progress.add(const PackInstallProgress(
      slug: 'golden-era', state: PackInstallState.verifying,
      bytesDone: 20 * 1024 * 1024, bytesTotal: 20 * 1024 * 1024, filesDone: 240, filesTotal: 240,
    ));
    await tester.pump();
    expect(find.text('Checking 240/240 files'), findsOneWidget);

    progress.add(const PackInstallProgress(
      slug: 'golden-era', state: PackInstallState.installed,
      bytesDone: 20 * 1024 * 1024, bytesTotal: 20 * 1024 * 1024, filesDone: 240, filesTotal: 240,
    ));
    release.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('install-progress')), findsNothing);
    expect(find.text('Installing'), findsNothing);
  });

  testWidgets('a failed install says so and lets the player try again', (tester) async {
    final service = FakePackService()..onInstall = (_) async => throw const PackInstallException('checksum mismatch');
    await pumpScreens(tester, location: '/packs', packs: [golden], packService: service);

    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Download failed. Check your connection and try again.'), findsOneWidget);
    expect(buttonIn(tester, 'Golden era').onPressed, isNotNull);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('says when the list cannot be loaded and offers to try again', (tester) async {
    await pumpScreens(tester, location: '/packs', packsError: const PacksApiException('GET /v1/packs returned 503'));
    await tester.pump();

    expect(find.textContaining("Couldn't load the packs"), findsOneWidget);
    expect(find.textContaining('503'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('says when no packs are published', (tester) async {
    await pumpScreens(tester, location: '/packs');
    await tester.pump();
    expect(find.text('No packs are published yet.'), findsOneWidget);
  });
}

