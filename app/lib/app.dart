import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/game/debug/clip_playback_debug_screen.dart';
import 'features/game/debug/sessions_debug_screen.dart';
import 'features/game/home_screen.dart';
import 'features/game/presentation/results_screen.dart';
import 'features/game/presentation/round_screen.dart';
import 'features/game/presentation/start_screen.dart';
import 'features/packs/presentation/packs_screen.dart';
import 'l10n/app_localizations.dart';

/// Bundled in `assets/fonts`. Latin text keeps the default font; Fidel falls back to this.
const ethiopicFontFamily = 'NotoSansEthiopic';

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const [ethiopicFontFamily]),
  );
}

/// The app's routes. Tests build their own router, starting anywhere.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/packs', builder: (context, state) => const PacksScreen()),
    GoRoute(path: '/start', builder: (context, state) => const StartScreen()),
    GoRoute(path: '/play', builder: (context, state) => const RoundScreen()),
    GoRoute(path: '/results', builder: (context, state) => const ResultsScreen()),
    GoRoute(
      path: '/debug/sessions',
      builder: (context, state) => const SessionsDebugScreen(),
    ),
    GoRoute(
      path: '/debug/clip-playback',
      builder: (context, state) => const ClipPlaybackDebugScreen(),
    ),
  ],
);

final _router = buildRouter();

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
