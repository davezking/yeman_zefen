import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/theme/app_theme.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';

/// The icon font that ships with the Flutter SDK. `flutter test` does not
/// load it, so every icon would be drawn as a square.
File _materialIconsFont() {
  const file = 'material_fonts/MaterialIcons-Regular.otf';
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [if (root != null) '$root/bin/cache/artifacts/$file'];
  // The test runner sits in <sdk>/bin/cache/artifacts/engine/<platform>/.
  for (
    var dir = File(Platform.resolvedExecutable).parent;
    dir.parent.path != dir.path;
    dir = dir.parent
  ) {
    candidates.add('${dir.path}/$file');
  }
  return candidates
      .map(File.new)
      .firstWhere(
        (f) => f.existsSync(),
        orElse: () => throw StateError(
          'MaterialIcons-Regular.otf not found in the Flutter SDK; icons would '
          'render as squares. Looked in: ${candidates.join(', ')}',
        ),
      );
}

/// Loads the bundled fonts, because tests otherwise draw every glyph as a
/// fixed-width square, which makes text wider than it really is and hides (or
/// invents) overflow. That includes the icons, whose font comes from the SDK.
/// Call from `setUpAll`.
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

  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(_materialIconsFont().readAsBytesSync().buffer),
      ),
    );
  await icons.load();
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
