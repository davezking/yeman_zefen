import 'package:yeman_zefen/core/ads/consent_service.dart';

/// Google's and Apple's answers, set by each test. [calls] records what was asked, in order.
class FakeConsentPlatform implements ConsentPlatform {
  var umpStatus = UmpStatus.unknown;
  var canRequest = false;
  var optionsRequired = false;
  var trackingAsked = false;
  var ios = false;
  var updateFails = false;

  /// What Google's form leaves behind when the player answers it.
  var statusAfterForm = UmpStatus.obtained;
  final calls = <String>[];

  @override
  Future<void> requestInfoUpdate() async {
    calls.add('update');
    if (updateFails) throw StateError('offline');
  }

  @override
  Future<UmpStatus> status() async => umpStatus;

  @override
  Future<bool> canRequestAds() async => canRequest;

  @override
  Future<bool> privacyOptionsRequired() async => optionsRequired;

  @override
  Future<void> showFormIfRequired() async {
    calls.add('form');
    umpStatus = statusAfterForm;
    canRequest = true;
  }

  @override
  Future<void> showPrivacyOptionsForm() async => calls.add('privacy');

  @override
  Future<bool> trackingUndetermined() async => ios && !trackingAsked;

  @override
  Future<void> requestTracking() async {
    calls.add('tracking');
    trackingAsked = true;
  }
}
