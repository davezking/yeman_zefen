import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/remote_config.dart';
import 'core/config/update_required_screen.dart';
import 'core/l10n/locale_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/account/ui/register_prompt_on_results.dart';
import 'features/game/debug/clip_playback_debug_screen.dart';
import 'features/game/debug/sessions_debug_screen.dart';
import 'features/game/presentation/consent_route.dart';
import 'features/game/presentation/home_route.dart';
import 'features/game/presentation/mode_route.dart';
import 'features/game/presentation/results_route.dart';
import 'features/game/presentation/round_route.dart';
import 'features/game/presentation/setup_route.dart';
import 'features/leaderboard/ui/leaderboard_page.dart';
import 'features/packs/presentation/offline_play_route.dart';
import 'features/settings/presentation/settings_route.dart';
import 'l10n/app_localizations.dart';

/// One theme per language (only the text differs), built once.
final _themes = <String, ThemeData>{};
ThemeData _themeFor(Locale locale) => _themes.putIfAbsent(locale.languageCode, () => buildAppTheme(locale));

/// The app's routes. Tests build their own router, starting anywhere.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeRoute()),
    GoRoute(path: '/mode', builder: (context, state) => const ModeRoute()),
    GoRoute(path: '/setup', builder: (context, state) => const SetupRoute()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsRoute()),
    GoRoute(path: '/packs', builder: (context, state) => const OfflinePlayRoute()),
    GoRoute(path: '/play', builder: (context, state) => const RoundRoute()),
    GoRoute(path: '/consent', builder: (context, state) => const ConsentRoute()),
    GoRoute(path: '/results', builder: (context, state) => const RegisterPromptOnResults(child: ResultsRoute())),
    GoRoute(path: '/leaderboard', builder: (context, state) => const LeaderboardPage()),
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

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateRequired = ref.watch(updateRequiredProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      // The player's language (or the device's, until they choose): changing it rebuilds the
      // whole app in the new language, with no restart.
      locale: locale,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: _themeFor(const Locale('en')),
      // The theme depends on the language, which is only known below MaterialApp.
      // An app too old to play shows only the update screen; the router below is not built.
      builder: (context, child) => Theme(
        data: _themeFor(Localizations.localeOf(context)),
        child: updateRequired ? const UpdateRequiredScreen() : child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
