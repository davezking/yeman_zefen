import 'dart:math';

/// Decides when an interstitial may show (FR-19, `docs/design/screens.md`).
///
/// Only between rounds: after the feedback, before the next clip starts, never while audio plays,
/// and only once at least N rounds (`interstitialEveryRounds` from `/v1/config`) have been played
/// since the last one. Never in the player's first session, and never after the last round, which
/// has no next clip. The count carries over from one session to the next while the app runs.
class AdPolicy {
  AdPolicy({required this.everyRounds});

  /// Read on every call, so a config refresh applies at once.
  final int Function() everyRounds;

  var _roundsSinceLast = 0;
  var _firstSession = true;

  /// Rounds played since the last interstitial, not counting the first session's.
  int get roundsSinceLast => _roundsSinceLast;

  /// A session starts. [firstSession] is true when the player has never finished one.
  void beginSession({required bool firstSession}) => _firstSession = firstSession;

  /// A round was played to an answer or a time-out. Skipped rounds do not count.
  void roundPlayed() {
    if (!_firstSession) _roundsSinceLast++;
  }

  /// Whether an interstitial may show now, at the end of a round's feedback.
  bool shouldShowInterstitial({required bool audioPlaying, required bool moreRounds}) =>
      !_firstSession && !audioPlaying && moreRounds && _roundsSinceLast >= max(1, everyRounds());

  /// An interstitial was shown. The count starts again.
  void interstitialShown() => _roundsSinceLast = 0;
}
