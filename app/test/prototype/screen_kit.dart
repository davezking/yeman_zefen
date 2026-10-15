import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/theme/app_theme.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';

export '../core/widgets/widget_kit.dart' show loadAppFonts;

/// The design's phone: 360 x 780 dp.
const phoneSize = Size(360, 780);

/// Pumps a whole screen on the design's phone, in [locale], at [textScale].
/// Layout overflow is thrown by Flutter in tests, so a screen that does not
/// fit fails right here (check `tester.takeException()`).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = phoneSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: buildAppTheme(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pump();
}

/// Both languages at both text scales the design requires.
const languages = [Locale('en'), Locale('am')];
const textScales = [1.0, 1.3];
