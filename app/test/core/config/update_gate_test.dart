import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/app.dart';
import 'package:yeman_zefen/core/config/remote_config.dart';
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
        overrides: [updateRequiredProvider.overrideWithValue(false)],
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
