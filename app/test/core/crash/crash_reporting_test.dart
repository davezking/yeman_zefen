import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/crash/crash_reporting.dart';

void main() {
  // Firebase is not started in tests, so reporting must be a silent no-op.
  test('reporting calls do nothing before Firebase starts', () {
    expect(() => setCrashUser('player-1'), returnsNormally);
    expect(() => setCrashUser(null), returnsNormally);
    expect(
      () => recordNonFatal(StateError('x'), null, reason: 'sync_parked'),
      returnsNormally,
    );
  });
}
