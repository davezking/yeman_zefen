import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/ads/ad_policy.dart';

void main() {
  var every = 3;
  late AdPolicy policy;

  setUp(() {
    every = 3;
    policy = AdPolicy(everyRounds: () => every);
  });

  bool due({bool audio = false, bool more = true}) => policy.shouldShowInterstitial(audioPlaying: audio, moreRounds: more);

  void play(int rounds) {
    for (var i = 0; i < rounds; i++) {
      policy.roundPlayed();
    }
  }

  test('never in the first session, and its rounds do not count', () {
    policy.beginSession(firstSession: true);
    play(10);
    expect(due(), isFalse);
    policy.beginSession(firstSession: false);
    expect(policy.roundsSinceLast, 0);
  });

  test('after N rounds, then counts again from the one shown', () {
    policy.beginSession(firstSession: false);
    play(2);
    expect(due(), isFalse);
    play(1);
    expect(due(), isTrue);
    policy.interstitialShown();
    expect(due(), isFalse);
    play(3);
    expect(due(), isTrue);
  });

  test('never while audio plays, and never after the last round', () {
    policy.beginSession(firstSession: false);
    play(3);
    expect(due(audio: true), isFalse);
    expect(due(more: false), isFalse);
  });

  test('stays due until one is shown, and carries over to the next session', () {
    policy.beginSession(firstSession: false);
    play(5);
    expect(due(), isTrue);
    policy.beginSession(firstSession: false);
    expect(due(), isTrue);
  });

  test('reads N on every call, and treats less than 1 as 1', () {
    policy.beginSession(firstSession: false);
    play(1);
    expect(due(), isFalse);
    every = 1;
    expect(due(), isTrue);
    every = 0;
    expect(due(), isTrue);
  });
}
