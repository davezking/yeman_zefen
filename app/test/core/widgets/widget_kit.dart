import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/theme/app_theme.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';

/// Loads the bundled fonts, because tests otherwise draw every glyph as a
/// fixed-width square, which makes text wider than it really is and hides (or
/// invents) overflow. Call from `setUpAll`.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(
          ByteData.view(File('assets/fonts/$f').readAsBytesSync().buffer),
        ),
      );
    }
    await loader.load();
  }

  await load('Poppins', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
      'Poppins-$w.ttf',
  ]);
  await load('Noto Sans Ethiopic', ['NotoSansEthiopic.ttf']);
}

/// Pumps [child] on a 360 dp wide screen (the design's phone width) in the
/// app theme, left-aligned in a padded column like a real screen.
Future<void> pumpComponent(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool disableAnimations = false,
  double height = 800,
}) async {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: buildAppTheme(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child],
          ),
        ),
      ),
    ),
  );
}
