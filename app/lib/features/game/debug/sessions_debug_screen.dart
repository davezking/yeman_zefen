import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_db.dart';
import '../data/session_store.dart';

/// One saved session, summarised for checking on a device.
class DebugSession {
  const DebugSession({
    required this.id,
    required this.createdAt,
    required this.mode,
    required this.rounds,
    required this.minResponseMs,
    required this.maxResponseMs,
    required this.offline,
    required this.prettyJson,
  });

  final String id;
  final int createdAt;
  final String mode;
  final int rounds;

  /// Null when there are no rounds.
  final int? minResponseMs;
  final int? maxResponseMs;
  final bool offline;
  final String prettyJson;

  /// A response faster than a person can react, which the server flags.
  bool get hasTooFastResponse => minResponseMs != null && minResponseMs! < 200;

  factory DebugSession.fromRow(PendingSession row) {
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    final rounds = (payload['rounds'] as List<dynamic>).cast<Map<String, dynamic>>();
    final times = [for (final r in rounds) r['responseMs'] as int];
    times.sort();
    return DebugSession(
      id: row.id,
      createdAt: row.createdAt,
      mode: payload['mode'] as String,
      rounds: rounds.length,
      minResponseMs: times.isEmpty ? null : times.first,
      maxResponseMs: times.isEmpty ? null : times.last,
      offline: payload['offline'] as bool,
      prettyJson: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }
}

class DebugSessionsData {
  const DebugSessionsData({required this.sessions, required this.clipErrors});
  final List<DebugSession> sessions;
  final int clipErrors;
}

final debugSessionsProvider = FutureProvider.autoDispose<DebugSessionsData>((ref) async {
  final db = ref.watch(appDbProvider);
  final rows = await (db.select(db.pendingSessions)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  return DebugSessionsData(
    sessions: [for (final r in rows) DebugSession.fromRow(r)],
    clipErrors: await SessionStore(db).clipErrorCount(),
  );
});

/// Throwaway screen for checking the sessions saved on the device: that the
/// payload is complete and that the response times look like a person's. Shown
/// in the dev flavor only.
class SessionsDebugScreen extends ConsumerWidget {
  const SessionsDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(debugSessionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved sessions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(debugSessionsProvider),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not read the sessions: $e')),
        data: (d) => ListView(
          children: [
            ListTile(title: Text('Clip errors: ${d.clipErrors}', key: const Key('clip-errors'))),
            const Divider(height: 1),
            if (d.sessions.isEmpty) const ListTile(title: Text('No saved sessions yet.')),
            for (final s in d.sessions)
              ExpansionTile(
                key: Key('session-${s.id}'),
                title: Text('${s.mode} · ${s.rounds} rounds'),
                subtitle: Text(
                  'responses ${s.minResponseMs ?? '-'}–${s.maxResponseMs ?? '-'} ms · '
                  '${s.offline ? 'offline' : 'online'}'
                  '${s.hasTooFastResponse ? ' · TOO FAST' : ''}',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(s.prettyJson, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
