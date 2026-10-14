import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/game/home_screen.dart';
import 'l10n/app_localizations.dart';

/// Bundled in `assets/fonts`. Latin text keeps the default font; Fidel falls back to this.
const ethiopicFontFamily = 'NotoSansEthiopic';

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const [ethiopicFontFamily]),
  );
}

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
  ],
);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
