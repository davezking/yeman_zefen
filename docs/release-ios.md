# Releasing the iOS app

iOS builds run on your Mac with Xcode, not in CI. Both platforms use the `prod` flavor and the version in `app/pubspec.yaml` (the single source; edit only its name, the build number is set at build time).

```
make ios-release        # check the config, build the obfuscated IPA: app/build/ios/ipa/*.ipa
# upload it to App Store Connect (step 5), then:
make ios-symbols        # dSYMs and Dart symbols to Crashlytics (step 6)
```

`make ios-release` is `app/tool/ios_release.sh build`. It refuses to build while `app/config/prod.json` has a placeholder `API_BASE` or real ad units with Google's sample AdMob app id (`app/tool/check_release_config.sh ios`), and from a checkout with uncommitted changes under `app/`. The build number is the UTC time (`YYMMDDHHMM`), so every upload is higher than the last; set `IOS_BUILD_NUMBER` to override. Release from a checkout of the tag.

## 1. Accounts and identifiers (once)

1. Enrol in the Apple Developer Program ($99/year) and sign in to Xcode with that Apple ID (Xcode > Settings > Accounts).
2. Bundle IDs per flavor: **prod `com.yemanzefen.yemanZefen`**, dev `com.yemanzefen.yemanZefen.dev`. They are set per build configuration in `ios/Runner.xcodeproj`; the Firebase iOS app for prod must use the prod one (`lib/core/config/firebase_options_prod.dart`). Android uses `com.yemanzefen.yeman_zefen`; the two are different on purpose and must not be mixed up in Firebase.
3. Open `app/ios/Runner.xcworkspace` in Xcode, select the Runner target > **Signing & Capabilities**, and for the prod configurations tick **Automatically manage signing** and pick your Team. Xcode registers the App ID, the certificates and the profiles. Commit the `DEVELOPMENT_TEAM` line it writes to `project.pbxproj`.

## 2. Capabilities

- **Sign in with Apple:** already declared in `ios/Runner/Runner.entitlements` and referenced by every Runner build configuration (`CODE_SIGN_ENTITLEMENTS`). With automatic signing, Xcode turns the capability on for the App ID. If Signing & Capabilities shows an error about it, enable it for the App ID in developer.apple.com > Certificates, Identifiers & Profiles.
- **Push notifications:** not used in v1. Do not add the capability or `aps-environment`.

## 3. Info.plist keys (already in `ios/Runner/Info.plist`)

- `NSUserTrackingUsageDescription`: one string with English first and Amharic below. It is shown as is, whatever the phone's language. Have a native speaker check the Amharic before submitting. The app asks after Google's consent form (`lib/core/ads/consent_service.dart`).
- `GADApplicationIdentifier`: `$(ADMOB_APP_ID)`, set per flavor in `ios/Flutter/prodRelease.xcconfig`. **It is Google's sample id until the AdMob app exists. Before release, replace it with the real iOS app id and put the real ad units in `config/prod.json` together** (`docs/ops.md`, Ads); the check script stops a mismatch.
- App Store Connect > App Privacy must say the app collects Device ID (advertising) and the other data AdMob and Firebase collect, to match the tracking prompt.

## 4. Build

`make ios-release`. The project uses **Swift Package Manager** for its plugins (Firebase included), not CocoaPods, so there is no `Podfile`: Xcode fetches the packages on the first build, into its DerivedData folder. Check that the archive is for scheme `prod` and the Release configuration of the prod flavor. The build uses the default export method (App Store Connect).

## 5. Upload to TestFlight

1. App Store Connect > Apps > create the app once (the prod bundle ID, name "Yeman Zefen").
2. Send the IPA with **Transporter** (Mac App Store, drag `app/build/ios/ipa/*.ipa` in and Deliver), or from the terminal with an App Store Connect API key (Users and Access > Integrations > Keys):
   `xcrun altool --upload-app --type ios --file build/ios/ipa/*.ipa --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>` (the `.p8` goes in `~/.appstoreconnect/private_keys/`). Check Apple's current documentation if `altool` has changed.
3. Wait for the "processing" email, answer the export compliance question (the app only uses standard encryption), and add the build to an internal TestFlight group.
4. Install it from the TestFlight app on a phone.

## 6. Crashlytics symbols (dSYMs and Dart symbols)

The IPA is obfuscated like the Android build, so Crashlytics needs two things: the dSYMs from the archive (native frames) and the Dart symbols (`--split-debug-info`). Download the prod iOS app's `GoogleService-Info.plist` from Firebase console > Project settings, keep it **outside the repository**, and run:

```
export IOS_GOOGLESERVICE_PLIST=~/secrets/GoogleService-Info-prod.plist
firebase login        # once; or set GOOGLE_APPLICATION_CREDENTIALS to a service account
make ios-symbols
```

The script finds Crashlytics' `upload-symbols` tool in Xcode's package checkout (DerivedData), which the build fills. Do it for every build you send out. The symbols of a build that was not uploaded cannot be recreated later, so keep `app/build/ios/archive` and `app/build/symbols-ios` until it is done.

## Checks before the first release

- The build installs from TestFlight and signs in with Apple.
- A forced crash on the TestFlight build shows up in Crashlytics with readable Dart and native frames.
