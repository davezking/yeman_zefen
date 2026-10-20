import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/theme/app_theme.dart';
import 'package:yeman_zefen/features/leaderboard/ui/leaderboard_screen.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';
import 'package:yeman_zefen/prototype/models.dart';

void main() {
  final entries = [
    const LeaderboardEntry(rank: 1, name: 'Selam', points: 900),
    const LeaderboardEntry(rank: 2, name: 'Abebe', points: 800, colorIndex: 1),
    const LeaderboardEntry(rank: 3, name: 'Me Myself', points: 700, colorIndex: 2),
    const LeaderboardEntry(rank: 4, name: 'Bad Name', points: 600, colorIndex: 3),
    const LeaderboardEntry(rank: 5, name: '', points: 500, colorIndex: 4),
  ];

  Future<void> pump(WidgetTester tester, {ValueChanged<LeaderboardEntry>? onReport}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const Locale('en')),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LeaderboardScreen(
          view: LeaderboardView(
            scope: LeaderboardScope.weekly,
            generationId: 0,
            entries: entries,
            user: const UserInfo.signedIn(displayName: 'Me Myself'),
            state: LeaderboardState.ready,
          ),
          onBack: () {},
          onScope: (_) {},
          onEra: (_) {},
          onSignIn: () {},
          onReport: onReport,
        ),
      ),
    );
  }

  testWidgets('tapping a row or a podium place reports its name', (tester) async {
    final reported = <String>[];
    await pump(tester, onReport: (e) => reported.add(e.name));

    await tester.tap(find.text('Bad Name'));
    await tester.tap(find.text('Selam'));
    expect(reported, ['Bad Name', 'Selam']);
  });

  testWidgets("the player's own name and a row with no name cannot be reported", (tester) async {
    final reported = <String>[];
    await pump(tester, onReport: (e) => reported.add(e.name));

    await tester.tap(find.text('Me Myself'));
    await tester.tap(find.text('5'));
    expect(reported, isEmpty);
  });

  testWidgets('screen readers hear the report action on reportable rows only', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, onReport: (_) {});

    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('^4, Bad Name'))).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('^3, Me Myself'))).getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('nothing is tappable without onReport', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Bad Name'));
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('^4, Bad Name'))).getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
  });
}
