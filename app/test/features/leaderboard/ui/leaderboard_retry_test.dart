import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/theme/app_theme.dart';
import 'package:yeman_zefen/features/leaderboard/ui/leaderboard_screen.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';
import 'package:yeman_zefen/prototype/models.dart';

void main() {
  Future<void> pump(WidgetTester tester, LeaderboardState state, VoidCallback onRetry) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Locale('en')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LeaderboardScreen(
          view: LeaderboardView(
            scope: LeaderboardScope.weekly,
            generationId: 0,
            entries: const [],
            user: const UserInfo.guest(),
            state: state,
          ),
          onBack: () {},
          onScope: (_) {},
          onEra: (_) {},
          onSignIn: () {},
          onRetry: onRetry,
        ),
      ),
    );
  }

  testWidgets('offline with nothing saved, "Try again" loads the board again', (tester) async {
    var retries = 0;
    await pump(tester, LeaderboardState.offlineNone, () => retries++);

    expect(find.text('Connect to the internet to see the leaderboard.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('an empty board has nothing to retry', (tester) async {
    await pump(tester, LeaderboardState.empty, () {});
    expect(find.text('Try again'), findsNothing);
  });
}
