# Apple App Store: privacy labels (answers)

Draft answers for App Store Connect > App Privacy. Apple treats **Used to Track You** as a specific term: data
combined with other companies' data for targeted advertising or shared with a data broker. The labels must match the
privacy policy and the App Tracking Transparency prompt (`app/ios/Runner/Info.plist`, `NSUserTrackingUsageDescription`).
Items marked **(confirm)** need checking against the SDK versions in use.

## Tracking

| Question | Answer |
|---|---|
| Does the app use data to track you? | **Yes** |
| Domains used for tracking | Google AdMob's ad domains (confirm the list from Google's SDK documentation). |

The app asks for tracking permission with App Tracking Transparency, after a finished game, when Google's consent
form is not required or has been answered. If the player says no, the advertising identifier is not used for
tracking.

## Data types

| Apple data type | Collected | Linked to the user | Used to track you | Purposes |
|---|---|---|---|---|
| **Contact info** > Email address | Yes (registered players only) | Yes | No | App functionality, account management |
| **Contact info** > Name | Yes (display name, optional) | Yes | No | App functionality |
| **Identifiers** > User ID | Yes (Firebase user ID) | Yes | No | App functionality, analytics, product personalization |
| **Identifiers** > Device ID | Yes (IDFA, only with permission; collected by the AdMob SDK) | Yes (or not linked, confirm) | **Yes**, for advertising | Third-party advertising |
| **Location** > Coarse location | Yes (country from IP, server side; AdMob also collects it) | Yes | **Yes**, for advertising, through AdMob (confirm: whether the server-side country counts) | App functionality, third-party advertising |
| **Usage data** > Product interaction | Yes (gameplay sessions) | Yes | No | App functionality, analytics |
| **Usage data** > Advertising data | Yes (ad views and clicks, collected by AdMob) | Yes | **Yes**, for advertising | Third-party advertising |
| **Diagnostics** > Crash data | Yes (Crashlytics) | Yes (the Firebase user ID) | No | App functionality |
| **Diagnostics** > Performance data | No (the app does not enable performance monitoring) | | | |
| **Diagnostics** > Other diagnostic data | No | | | |
| **Financial info, Health, Sensitive info, Contacts, User content, Browsing history, Search history, Surroundings, Body, Other data** | No | | | |

## Notes for the form

- Apple expects the label to cover the SDKs' data too. The Google Mobile Ads SDK and Firebase publish their own
  privacy details, and the labels must include what they collect. (confirm against the versions in `app/pubspec.lock`)
- Apple's privacy manifest (`app/ios/Runner/PrivacyInfo.xcprivacy`) mirrors these answers, and Xcode bundles it with
  the app. It has two open items: `NSPrivacyTrackingDomains` is empty until the AdMob tracking domains are confirmed
  from Google's SDK manifest, and `NSPrivacyAccessedAPITypes` is empty because the app's own code uses no required-reason
  API. Check both against the SDK manifests in the first TestFlight build. (confirm)
- Update the labels whenever a new SDK or data type is added, as Apple requires.
