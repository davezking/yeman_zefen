import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/data/packs_api.dart';
import 'package:yeman_zefen/features/settings/application/settings_providers.dart';

import '../game/presentation/screen_kit.dart';

const _signedIn = AuthState(uid: 'u1', isAnonymous: false, providers: ['google.com']);

PackListing _listing(String slug, int version) => PackListing(
      slug: slug,
      nameAm: 'a',
      nameEn: 'Golden era',
      version: version,
      manifestUrl: 'https://cdn.test/$slug/v$version/manifest.json',
      trackCount: 3,
      totalBytes: 1,
      publishedAt: 1,
    );

void main() {
  testWidgets('a guest sees the guest line and no sign-out row', (tester) async {
    await pumpScreens(tester, location: '/settings');
    expect(find.text('Playing as a guest'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('a signed-in player sees the sign-out row', (tester) async {
    await pumpScreens(tester, location: '/settings', auth: _signedIn);
    await tester.pump();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Playing as a guest'), findsNothing);
  });

  testWidgets('the sound switch is saved on the phone and read back', (tester) async {
    final h = await pumpScreens(tester, location: '/settings');
    expect(h.container.read(soundOnProvider), isTrue);

    await tester.tap(find.text('Sound effects'));
    await tester.pump();

    expect(h.container.read(soundOnProvider), isFalse);
    final db = h.container.read(appDbProvider);
    final row = await (db.select(db.appSettings)..where((t) => t.key.equals('sound'))).getSingle();
    expect(row.value, '0');
  });

  testWidgets('a newer pack on the list gets the update badge', (tester) async {
    await pumpScreens(
      tester,
      location: '/settings',
      installed: {'golden-era': 1},
      packs: [_listing('golden-era', 2)],
    );
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
  });

  testWidgets('no badge when the installed pack is current', (tester) async {
    await pumpScreens(
      tester,
      location: '/settings',
      installed: {'golden-era': 2},
      packs: [_listing('golden-era', 2)],
    );
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('Offline play opens the packs screen', (tester) async {
    final h = await pumpScreens(tester, location: '/settings');
    await tester.tap(find.textContaining('Offline play'));
    await tester.pumpAndSettle();
    expect(h.location, '/packs');
  });
}
