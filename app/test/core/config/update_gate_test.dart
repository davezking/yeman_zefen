import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/app.dart';
import 'package:drift/native.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/config/remote_config.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/net/network_kind.dart';
import 'package:yeman_zefen/features/game/application/play_setup.dart';
import 'package:yeman_zefen/features/settings/application/settings_providers.dart';
import 'package:yeman_zefen/core/config/update_required_screen.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';

void main() {
  testWidgets('an app older than the minimum shows only the update screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [updateRequiredProvider.overrideWithValue(true)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.text('Update needed'), findsOneWidget);
  });

  testWidgets('an app that meets the minimum starts normally', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateRequiredProvider.overrideWithValue(false),
          // The first screen reads the database, the account and the network; none is real here.
          appDbProvider.overrideWith((ref) {
            final db = AppDb(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          authStateProvider.overrideWith((ref) => Stream.value(AuthState.signedOut)),
          currentNetworkProvider.overrideWith((ref) => Stream.value(NetworkKind.unmetered)),
          installedPacksSummaryProvider.overrideWith((ref) => Stream.value(const InstalledPacksSummary(count: 0, bytes: 0))),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateRequiredScreen), findsNothing);
  });

  testWidgets('the update screen has the Amharic text too', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('am'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const UpdateRequiredScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ዝማኔ ያስፈልጋል'), findsOneWidget);
  });
}
