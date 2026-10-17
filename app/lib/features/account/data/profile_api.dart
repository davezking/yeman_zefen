import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/http/api_client.dart';
import '../../../core/http/api_providers.dart';
import '../../../prototype/models.dart';

/// `PUT /v1/me` with the display name the player picked.
Future<void> saveDisplayName(ApiClient api, String name) => api.putJson('/v1/me', body: {'displayName': name});

/// The caller's display name from `GET /v1/me`, or null when none is chosen yet. Throws an
/// [ApiException] when the request fails, so a caller can tell "no name" from "offline".
Future<String?> fetchDisplayName(ApiClient api) async {
  final json = await api.getJson('/v1/me');
  final name = json is Map<String, Object?> ? json['displayName'] : null;
  return name is String && name.isNotEmpty ? name : null;
}

/// The registered player's display name, or null for a guest, before a name is chosen, or
/// offline. Refreshed when the account changes, and invalidated after a name is saved.
final ownNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final auth = ref.watch(authStateProvider).value ?? AuthState.signedOut;
  // A guest's name is never shown, so it is not read.
  if (!auth.hasUid || auth.isAnonymous) return null;
  try {
    return await fetchDisplayName(ref.watch(apiClientProvider));
  } on ApiException {
    return null;
  }
});

/// What a failed name save means on the name step. `name_taken` is the server's answer when
/// another player has the name; the server does not enforce unique names yet, so this only
/// applies once it does. Anything else (offline, a server error, a name the server refused) is
/// [NameError.failed].
NameError nameErrorFor(ApiException e) => e.code == 'name_taken' ? NameError.taken : NameError.failed;

/// Whether the name is long enough to send once trimmed. The server allows 2 to 24 characters
/// and checks the rest; what it refuses comes back as [NameError.failed].
NameError nameLengthError(String raw) {
  final name = raw.trim();
  return name.runes.length < 2 ? NameError.tooShort : NameError.none;
}
