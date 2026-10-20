import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/ads/consent_service.dart';

import 'fake_consent_platform.dart';

void main() {
  late FakeConsentPlatform platform;
  late ConsentService service;
  var adsStarted = 0;

  ConsentService make({bool enabled = true}) =>
      ConsentService(platform, enabled: enabled, onAdsAllowed: () async => adsStarted++);

  setUp(() {
    adsStarted = 0;
    platform = FakeConsentPlatform();
    service = make();
  });

  tearDown(() => service.dispose());

  test('start-up refreshes the status without showing anything, and starts ads only when allowed', () async {
    platform.umpStatus = UmpStatus.required;
    await service.startup();
    expect(platform.calls, ['update']);
    expect(adsStarted, 0, reason: 'no ad request before consent');
    expect(service.askAfterGame, ConsentAsk.form);
  });

  test('outside consent regions ads start at once and nothing is asked', () async {
    platform
      ..umpStatus = UmpStatus.notRequired
      ..canRequest = true;
    await service.startup();
    expect(adsStarted, 1);
    expect(service.askAfterGame, ConsentAsk.none);
    expect(service.privacyOptionsRequired.value, isFalse);
  });

  test('offline start-up keeps the stored answer', () async {
    platform
      ..updateFails = true
      ..umpStatus = UmpStatus.obtained
      ..canRequest = true;
    await service.startup();
    expect(adsStarted, 1);
    expect(service.askAfterGame, ConsentAsk.none);
  });

  test('the form, then Apple\'s question on iOS, then ads and the privacy options row', () async {
    platform
      ..ios = true
      ..umpStatus = UmpStatus.required;
    await service.startup();
    expect(service.askAfterGame, ConsentAsk.form);

    platform.optionsRequired = true;
    await service.showForm();
    expect(platform.calls, ['update', 'form', 'tracking']);
    expect(adsStarted, 1);
    expect(service.askAfterGame, ConsentAsk.none);
    expect(service.privacyOptionsRequired.value, isTrue);
  });

  test('an unanswered form is asked again after the next game', () async {
    platform
      ..umpStatus = UmpStatus.required
      ..statusAfterForm = UmpStatus.required;
    await service.startup();
    await service.showForm();
    expect(service.askAfterGame, ConsentAsk.form);
  });

  test('on iOS outside consent regions only Apple\'s question is due, once', () async {
    platform
      ..ios = true
      ..umpStatus = UmpStatus.notRequired
      ..canRequest = true;
    await service.startup();
    expect(service.askAfterGame, ConsentAsk.tracking);
    await service.requestTracking();
    expect(platform.calls, ['update', 'tracking']);
    expect(service.askAfterGame, ConsentAsk.none);
  });

  test('privacy options open Google\'s form and refresh the status', () async {
    platform
      ..umpStatus = UmpStatus.obtained
      ..optionsRequired = true;
    await service.startup();
    platform.canRequest = true;
    await service.openPrivacyOptions();
    expect(platform.calls.last, 'privacy');
    expect(adsStarted, 1);
  });

  test('a build without ads asks nothing', () async {
    service.dispose();
    service = make(enabled: false);
    platform
      ..ios = true
      ..umpStatus = UmpStatus.required;
    await service.startup();
    expect(platform.calls, isEmpty);
    expect(service.askAfterGame, ConsentAsk.none);
  });
}
