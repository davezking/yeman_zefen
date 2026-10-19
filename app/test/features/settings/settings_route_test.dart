import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/data/catalog_refresher.dart';
import 'package:yeman_zefen/features/settings/application/settings_providers.dart';

import '../game/presentation/screen_kit.dart';

const _signedIn = AuthState(uid: 'u1', isAnonymous: false, providers: ['google.com']);

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

  Future<void> installedWithCatalog(Harness h, {required int installed, required int known}) async {
    final db = h.container.read(appDbProvider);
    await db.into(db.installedPacks).insert(
          InstalledPacksCompanion.insert(
            slug: 'golden-era',
            version: installed,
            manifestJson: '{}',
            installedAt: 1,
            totalBytes: 1,
          ),
        );
    await db.into(db.appSettings).insert(
          AppSettingsCompanion.insert(key: CatalogRefresher.versionKey('golden-era'), value: '$known'),
        );
    await h.tester.pumpAndSettle();
  }

  testWidgets('a newer version in the catalog badges Offline play and the Settings tab', (tester) async {
    final h = await pumpScreens(tester, location: '/settings');
    await installedWithCatalog(h, installed: 1, known: 2);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings, Update available'), findsOneWidget);
  });

  testWidgets('no badge when the installed pack is current', (tester) async {
    final h = await pumpScreens(tester, location: '/settings');
    await installedWithCatalog(h, installed: 2, known: 2);
    expect(find.text('Update available'), findsNothing);
    expect(find.bySemanticsLabel('Settings, Update available'), findsNothing);
  });

  testWidgets('Home badges the Settings tab, and never asks to download', (tester) async {
    final h = await pumpScreens(tester);
    await installedWithCatalog(h, installed: 1, known: 2);
    expect(find.bySemanticsLabel('Settings, Update available'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('Offline play opens the packs screen', (tester) async {
    final h = await pumpScreens(tester, location: '/settings');
    await tester.tap(find.textContaining('Offline play'));
    await tester.pumpAndSettle();
    expect(h.location, '/packs');
  });
}
