import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/http/api_client.dart';
import '../../../core/http/api_providers.dart';
import '../../../prototype/models.dart';
import '../../account/data/profile_api.dart';
import '../data/leaderboard_api.dart';

final leaderboardApiProvider = Provider<LeaderboardApi>((ref) => LeaderboardApi(ref.watch(apiClientProvider)));

/// The scope and era the board is showing. Era 0 is all eras.
@immutable
class LeaderboardQuery {
  const LeaderboardQuery({this.scope = LeaderboardScope.weekly, this.generationId = 0});

  final LeaderboardScope scope;
  final int generationId;

  @override
  bool operator ==(Object other) =>
      other is LeaderboardQuery && other.scope == scope && other.generationId == generationId;

  @override
  int get hashCode => Object.hash(scope, generationId);
}

class LeaderboardQueryNotifier extends Notifier<LeaderboardQuery> {
  @override
  LeaderboardQuery build() => const LeaderboardQuery();

  void setScope(LeaderboardScope scope) => state = LeaderboardQuery(scope: scope, generationId: state.generationId);

  void setEra(int generationId) => state = LeaderboardQuery(scope: state.scope, generationId: generationId);
}

final leaderboardQueryProvider = NotifierProvider<LeaderboardQueryNotifier, LeaderboardQuery>(
  LeaderboardQueryNotifier.new,
);

/// The board for the query, as the screen shows it. When the board itself cannot be read
/// (offline, a server error, an answer the app cannot parse) the view is
/// [LeaderboardState.offlineNone]: the screen has a state for it. When only the player's own row
/// cannot be read, the board still shows, without that row.
final leaderboardProvider = FutureProvider.autoDispose<LeaderboardView>((ref) async {
  final query = ref.watch(leaderboardQueryProvider);
  final auth = ref.watch(authStateProvider).value ?? AuthState.signedOut;
  final api = ref.watch(leaderboardApiProvider);
  final registered = auth.hasUid && !auth.isAnonymous;
  // All three start at once. A guest's own row is not read: the server answers 403 to a guest.
  final nameFuture = ref.watch(ownNameProvider.future);
  final topFuture = api.top(query.scope, query.generationId);
  final meFuture = registered ? _ownRow(api, query) : Future<LeaderboardEntry?>.value();

  // The board is awaited first: it is the only one of the three that can fail.
  List<LeaderboardEntry> entries;
  LeaderboardState state;
  try {
    entries = await topFuture;
    state = entries.isEmpty ? LeaderboardState.empty : LeaderboardState.ready;
  } on ApiException {
    (entries, state) = (const [], LeaderboardState.offlineNone);
  } on FormatException {
    (entries, state) = (const [], LeaderboardState.offlineNone);
  }
  final name = await nameFuture;
  final me = await meFuture;
  return LeaderboardView(
    scope: query.scope,
    generationId: query.generationId,
    entries: entries,
    user: registered ? UserInfo.signedIn(displayName: name ?? '', weeklyRank: me?.rank) : const UserInfo.guest(),
    me: me == null ? null : LeaderboardEntry(rank: me.rank, name: name ?? '', points: me.points),
    state: state,
  );
});

/// The player's own row, or null when it cannot be read. The board shows without it.
Future<LeaderboardEntry?> _ownRow(LeaderboardApi api, LeaderboardQuery query) async {
  try {
    return await api.me(query.scope, query.generationId, displayName: null);
  } on ApiException {
    return null;
  } on FormatException {
    return null;
  }
}
