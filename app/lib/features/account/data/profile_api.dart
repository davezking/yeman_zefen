import '../../../core/http/api_client.dart';
import '../../../prototype/models.dart';

/// `PUT /v1/me` with the display name the player picked.
Future<void> saveDisplayName(ApiClient api, String name) => api.putJson('/v1/me', body: {'displayName': name});

/// What a failed name save means on the name step. `name_taken` is the server's answer when
/// another player has the name; the server does not enforce unique names yet, so this only
/// applies once it does. Any other failure is not the name's fault and returns [NameError.none].
NameError nameErrorFor(ApiException e) => e.code == 'name_taken' ? NameError.taken : NameError.none;

/// Trims the name the way the server does (surrounding space out, runs of spaces collapsed), and
/// reports whether it is long enough to send. The server allows 2 to 24 characters.
NameError nameLengthError(String raw) {
  final name = raw.trim();
  return name.runes.length < 2 ? NameError.tooShort : NameError.none;
}
