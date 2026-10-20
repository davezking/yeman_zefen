import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/ads/consent_service.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/features/account/data/account_manager.dart';
import 'package:yeman_zefen/features/settings/presentation/settings_route.dart';
import 'package:yeman_zefen/prototype/models.dart' show SignInProvider;
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/packs/data/catalog_refresher.dart';
import 'package:yeman_zefen/features/settings/application/settings_providers.dart';

import '../../core/ads/fake_consent_platform.dart';
import '../game/presentation/screen_kit.dart';

const _signedIn = AuthState(uid: 'u1', isAnonymous: false, providers: ['google.com']);

/// Records what the settings screen asked of the account. [deleteWith] runs in place of a deletion.
class FakeAccountManager implements AccountManager {
  final calls = <String>[];
  Future<DeleteOutcome> Function(PasswordPrompt askPassword)? deleteWith;

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<DeleteOutcome> deleteAccount({required PasswordPrompt askPassword}) async {
    calls.add('delete');
    return (deleteWith ?? (_) async => DeleteOutcome.deleted)(askPassword);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The dialog's button labelled [text] (a title can say the same).
Finder _inDialog(String text) => find.descendant(
      of: find.byType(AppDialog),
      matching: find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate((w) => w is PrimaryButton || w is SecondaryButton),
      ),
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

  testWidgets('"Ad privacy choices" shows only where Google requires it, and opens its form', (tester) async {
    final platform = FakeConsentPlatform()..umpStatus = UmpStatus.obtained;
    final consent = ConsentService(platform, onAdsAllowed: () async {});
    addTearDown(consent.dispose);
    await pumpScreens(tester, location: '/settings', consent: consent);
    expect(find.text('Ad privacy choices'), findsNothing);

    platform.optionsRequired = true;
    await tester.runAsync(consent.startup);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Ad privacy choices'), 100);
    await tester.tap(find.text('Ad privacy choices'));
    await tester.pump();
    expect(platform.calls, contains('privacy'));
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

  testWidgets('a signed-in player sees how they sign in', (tester) async {
    await pumpScreens(tester, location: '/settings', auth: _signedIn);
    await tester.pump();
    expect(find.text('Signed in with Google'), findsOneWidget);
  });

  test('provider ids are named in a fixed order, unknown ones left out', () {
    expect(signInProviders(['password', 'google.com', 'phone']), [SignInProvider.google, SignInProvider.email]);
    expect(signInProviders(['google.com', 'apple.com']), [SignInProvider.apple, SignInProvider.google]);
  });

  group('sign out', () {
    testWidgets('warns about the rank, then signs out and says so', (tester) async {
      final manager = FakeAccountManager();
      await pumpScreens(tester, location: '/settings', auth: _signedIn, accountManager: manager);
      await tester.pump();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign in again to see your rank on the leaderboard.'), findsOneWidget);

      await tester.tap(_inDialog('Sign out'));
      await tester.pumpAndSettle();
      expect(manager.calls, ['signOut']);
      expect(find.text("Signed out. You're playing as a guest."), findsOneWidget);
    });
  });

  group('delete account', () {
    Future<FakeAccountManager> openDelete(WidgetTester tester) async {
      // A phone-sized screen tall enough to show the row above the bottom bar.
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final manager = FakeAccountManager();
      await pumpScreens(tester, location: '/settings', auth: _signedIn, accountManager: manager);
      await tester.pump();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      return manager;
    }

    testWidgets('asks twice, then deletes and says so', (tester) async {
      final manager = await openDelete(tester);
      await tester.tap(_inDialog('Delete my account'));
      await tester.pumpAndSettle();
      expect(manager.calls, isEmpty);
      expect(find.text('Delete your account now?'), findsOneWidget);

      await tester.tap(_inDialog('Delete account'));
      await tester.pumpAndSettle();
      expect(manager.calls, ['delete']);
      expect(find.text("Your account was deleted. You're playing as a guest."), findsOneWidget);
    });

    testWidgets('cancelling either step deletes nothing', (tester) async {
      final manager = await openDelete(tester);
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete my account'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      expect(manager.calls, isEmpty);
    });

    Future<void> confirmBoth(WidgetTester tester) async {
      await tester.tap(_inDialog('Delete my account'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete account'));
      await tester.pump();
    }

    testWidgets('shows that it is deleting while it runs', (tester) async {
      final manager = await openDelete(tester);
      final done = Completer<DeleteOutcome>();
      manager.deleteWith = (_) => done.future;
      await confirmBoth(tester);
      await tester.pump();
      expect(find.text('Deleting your account…'), findsOneWidget);
      done.complete(DeleteOutcome.cancelled);
      await tester.pumpAndSettle();
      expect(find.text('Deleting your account…'), findsNothing);
      // A cancelled sign-in says nothing.
      expect(find.byType(SnackBar), findsNothing);
    });

    // The "deleting" spinner keeps going under the prompt, so nothing settles: time is pumped.
    testWidgets('an email account is asked for its password', (tester) async {
      Future<void> frames() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final manager = await openDelete(tester);
      final typed = <String?>[];
      manager.deleteWith = (ask) async {
        typed.add(await ask(wrongPassword: false));
        typed.add(await ask(wrongPassword: true));
        return DeleteOutcome.cancelled;
      };
      await confirmBoth(tester);
      await frames();
      expect(find.text("Confirm it's you"), findsOneWidget);
      expect(find.text('Wrong email or password.'), findsNothing);
      await tester.enterText(find.byType(TextField), 'secret1');
      await tester.tap(_inDialog('Delete my account'));
      await frames();

      expect(find.text('Wrong email or password.'), findsOneWidget);
      await tester.tap(_inDialog('Cancel'));
      await frames();
      expect(typed, ['secret1', null]);
    });

    testWidgets('a failure says what happened', (tester) async {
      final manager = await openDelete(tester);
      manager.deleteWith = (_) async => throw const NetworkException('offline');
      await confirmBoth(tester);
      await tester.pumpAndSettle();
      expect(find.text('No internet connection. Connect and try again.'), findsOneWidget);
      expect(find.text('Deleting your account…'), findsNothing);
    });

    testWidgets('a half-done deletion asks to try again', (tester) async {
      final manager = await openDelete(tester);
      manager.deleteWith = (_) async => throw const DeleteIncompleteException();
      await confirmBoth(tester);
      await tester.pumpAndSettle();
      expect(find.text("Your scores were deleted, but the account wasn't. Try again to finish."), findsOneWidget);
    });
  });
}
