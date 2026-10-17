import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/http/api_client.dart';
import '../../../core/http/api_providers.dart';
import '../../../prototype/models.dart';
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

/// The signed-in player's display name from `GET /v1/me`, or null when none is chosen yet (or
/// the device is offline). Refreshed after a sign-in or a name change.
final ownNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final auth = ref.watch(authStateProvider).value ?? AuthState.signedOut;
  if (!auth.hasUid) return null;
  try {
    final json = await ref.watch(apiClientProvider).getJson('/v1/me');
    final name = json is Map<String, Object?> ? json['displayName'] : null;
    return name is String ? name : null;
  } on ApiException {
    return null;
  }
});

/// The board for the query, as the screen shows it. A failed request (offline, server error)
/// becomes [LeaderboardState.offlineNone] rather than an error: the screen has a state for it.
final leaderboardProvider = FutureProvider.autoDispose<LeaderboardView>((ref) async {
  final query = ref.watch(leaderboardQueryProvider);
  final auth = ref.watch(authStateProvider).value ?? AuthState.signedOut;
  final api = ref.watch(leaderboardApiProvider);
  final name = await ref.watch(ownNameProvider.future);
  try {
    final entries = await api.top(query.scope, query.generationId);
    // The guest's row is not read: the server answers 403 to a guest.
    final me = auth.hasUid && !auth.isAnonymous
        ? await api.me(query.scope, query.generationId, displayName: name)
        : null;
    return LeaderboardView(
      scope: query.scope,
      generationId: query.generationId,
      entries: entries,
      user: auth.hasUid && !auth.isAnonymous
          ? UserInfo.signedIn(displayName: name ?? '', weeklyRank: me?.rank)
          : const UserInfo.guest(),
      me: me,
      state: entries.isEmpty ? LeaderboardState.empty : LeaderboardState.ready,
    );
  } on ApiException {
    return LeaderboardView(
      scope: query.scope,
      generationId: query.generationId,
      entries: const [],
      user: const UserInfo.guest(),
      state: LeaderboardState.offlineNone,
    );
  }
});
