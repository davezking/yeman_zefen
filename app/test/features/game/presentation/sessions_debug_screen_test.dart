import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/game/debug/sessions_debug_screen.dart';

PendingSession row(
  String id, {
  List<int> times = const [2500, 1800, 3100],
  bool offline = true,
  String mode = 'intro',
  int attempts = 0,
  bool parked = false,
  String? lastError,
}) {
  final payload = {
    'id': id,
    'mode': mode,
    'generationId': 0,
    'difficulty': 'medium',
    'clientStartedAt': 1,
    'clientEndedAt': 2,
    'offline': offline,
    'rounds': [
      for (var i = 0; i < times.length; i++)
        {'trackId': i + 1, 'question': 'song', 'optionIds': [1, 2, 3, 4], 'chosenId': i + 1, 'responseMs': times[i], 'hintUsed': false},
    ],
    'ads': {'interstitialShown': 0, 'rewardedCompleted': 0},
  };
  return PendingSession(id: id, payloadJson: jsonEncode(payload), createdAt: 100, attempts: attempts, nextAttemptAt: 0, parked: parked, lastError: lastError);
}

void main() {
  test('summarises a saved session', () {
    final s = DebugSession.fromRow(row('a'));
    expect(s.rounds, 3);
    expect(s.minResponseMs, 1800);
    expect(s.maxResponseMs, 3100);
    expect(s.offline, isTrue);
    expect(s.hasTooFastResponse, isFalse);
    expect(s.prettyJson, contains('"responseMs": 2500'));
  });

  test('notices a response faster than a person can react', () {
    expect(DebugSession.fromRow(row('a', times: [150, 2000])).hasTooFastResponse, isTrue);
    expect(DebugSession.fromRow(row('a', times: [200, 2000])).hasTooFastResponse, isFalse);
  });

  test('copes with a session that has no rounds', () {
    final s = DebugSession.fromRow(row('a', times: []));
    expect(s.rounds, 0);
    expect(s.minResponseMs, isNull);
    expect(s.hasTooFastResponse, isFalse);
  });

  Future<void> pump(WidgetTester tester, DebugSessionsData data) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [debugSessionsProvider.overrideWith((ref) async => data)],
        child: const MaterialApp(home: SessionsDebugScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('lists the sessions with their response time range and the clip error count', (tester) async {
    await pump(
      tester,
      DebugSessionsData(
        sessions: [DebugSession.fromRow(row('a')), DebugSession.fromRow(row('b', times: [150, 900], offline: false, mode: 'middle'))],
        clipErrors: 2,
      ),
    );

    expect(find.text('Clip errors: 2'), findsOneWidget);
    expect(find.text('intro · 3 rounds'), findsOneWidget);
    expect(find.text('responses 1800–3100 ms · offline'), findsOneWidget);
    expect(find.text('middle · 2 rounds'), findsOneWidget);
    expect(find.text('responses 150–900 ms · online · TOO FAST'), findsOneWidget);
  });

  testWidgets('shows why a session is waiting or parked', (tester) async {
    await pump(
      tester,
      DebugSessionsData(
        sessions: [
          DebugSession.fromRow(row('a', attempts: 2, lastError: '500 internal: boom')),
          DebugSession.fromRow(row('b', mode: 'middle', attempts: 1, parked: true, lastError: '422 invalid_session: no')),
        ],
        clipErrors: 0,
      ),
    );

    expect(find.textContaining('retrying (2)'), findsOneWidget);
    expect(find.textContaining('500 internal: boom'), findsOneWidget);
    expect(find.textContaining('PARKED'), findsOneWidget);
    expect(find.textContaining('422 invalid_session: no'), findsOneWidget);
  });

  testWidgets('shows the payload when a session is opened', (tester) async {
    await pump(tester, DebugSessionsData(sessions: [DebugSession.fromRow(row('a'))], clipErrors: 0));

    await tester.tap(find.text('intro · 3 rounds'));
    await tester.pumpAndSettle();

    expect(find.textContaining('"clientStartedAt"', findRichText: true), findsOneWidget);
  });

  testWidgets('says when nothing is saved', (tester) async {
    await pump(tester, const DebugSessionsData(sessions: [], clipErrors: 0));
    expect(find.text('No saved sessions yet.'), findsOneWidget);
  });
}
