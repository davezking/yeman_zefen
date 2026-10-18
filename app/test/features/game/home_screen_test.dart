import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/home_screen.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';

Widget _wrap(Locale locale) => ProviderScope(
      child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    ));

void main() {
  testWidgets('shows the Amharic app name', (tester) async {
    await tester.pumpWidget(_wrap(const Locale('am')));
    expect(find.text('የማን ዘፈን'), findsOneWidget);
  });

  testWidgets('shows Amharic sample strings in am', (tester) async {
    await tester.pumpWidget(_wrap(const Locale('am')));
    expect(find.text('ጀምር'), findsOneWidget);
  });

  testWidgets('shows English sample strings in en', (tester) async {
    await tester.pumpWidget(_wrap(const Locale('en')));
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Listen to the clip and pick the song.'), findsOneWidget);
  });
}
