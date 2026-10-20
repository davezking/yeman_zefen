import '../../../core/http/api_client.dart';
import '../../../prototype/models.dart';

/// The board's rows and the caller's own row, as the leaderboard screen shows them.
class BoardAnswer {
  const BoardAnswer({required this.entries, this.me});

  /// Everyone ranked, best first.
  final List<LeaderboardEntry> entries;

  /// The caller's own row, or null when they are not ranked this period.
  final LeaderboardEntry? me;
}

/// `GET /v1/leaderboard`, `GET /v1/leaderboard/me` and `POST /v1/reports/name`.
class LeaderboardApi {
  LeaderboardApi(this.api);

  final ApiClient api;

  /// The API's name for a scope: `week` (this ISO week) or `all`.
  static String periodFor(LeaderboardScope scope) => switch (scope) {
    LeaderboardScope.weekly => 'week',
    LeaderboardScope.allTime => 'all',
  };

  /// The top of the board. Throws an [ApiException] when the request fails.
  Future<List<LeaderboardEntry>> top(LeaderboardScope scope, int generationId) async {
    final json = await api.getJson(
      '/v1/leaderboard',
      query: {'period': periodFor(scope), 'generation': '$generationId'},
    );
    return parseEntries(json);
  }

  /// The caller's own row. Registered players only: the server answers 403 to a guest.
  Future<LeaderboardEntry?> me(LeaderboardScope scope, int generationId, {required String? displayName}) async {
    final json = await api.getJson(
      '/v1/leaderboard/me',
      query: {'period': periodFor(scope), 'generation': '$generationId'},
    );
    return parseMe(json, displayName: displayName);
  }

  /// Reports a name on the board as offensive, for the moderators. The server answers the same
  /// whether or not anyone has that name. Throws an [ApiException] when the request fails.
  Future<void> reportName(String displayName) async {
    await api.postJson('/v1/reports/name', body: {'displayName': displayName});
  }
}

/// Parses `{ entries: [{ rank, displayName, points }] }`. A row with no name (a player who has not
/// chosen one yet) shows an empty name; the screen never invents one.
List<LeaderboardEntry> parseEntries(Object? json) {
  final rows = _map(json)['entries'];
  if (rows is! List<Object?>) {
    throw const FormatException('entries is not a list');
  }
  return [
    for (var i = 0; i < rows.length; i++)
      LeaderboardEntry(
        rank: _int(_map(rows[i])['rank']),
        name: _map(rows[i])['displayName'] as String? ?? '',
        points: _int(_map(rows[i])['points']),
        colorIndex: i,
      ),
  ];
}

/// Parses `{ me: { points, rank } | null }`. The name is the caller's own, from `GET /v1/me`.
LeaderboardEntry? parseMe(Object? json, {required String? displayName}) {
  final me = _map(json)['me'];
  if (me == null) {
    return null;
  }
  return LeaderboardEntry(rank: _int(_map(me)['rank']), name: displayName ?? '', points: _int(_map(me)['points']));
}

Map<String, Object?> _map(Object? v) {
  if (v is Map<String, Object?>) return v;
  throw const FormatException('not an object');
}

int _int(Object? v) {
  if (v is int) return v;
  throw const FormatException('not a whole number');
}
