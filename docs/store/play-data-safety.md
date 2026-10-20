# Google Play: Data safety form (answers)

Draft answers for Play Console > App content > Data safety. Each row says what to pick and why. Answers
marked **(confirm)** depend on the Google Mobile Ads SDK or Firebase version in use, or on a Play policy that
changes, so check them in Play Console before submitting. The privacy policy (`docs/legal/privacy-policy.md`)
must say the same things.

## Overview

| Question | Answer | Why |
|---|---|---|
| Does the app collect or share any of the required user data types? | **Yes** | Firebase, Crashlytics and AdMob collect data (see below). |
| Is all user data encrypted in transit? | **Yes** | HTTPS for all requests (Firebase, Cloudflare, AdMob). |
| Do you provide a way for users to request that their data is deleted? | **Yes**: in the app, Settings > Account > Delete account, and on the web at **https://api.[domain]/account-deletion**. | Play requires apps that let users create an account to give a web link where they can ask for deletion without reinstalling the app. The Worker serves that page (`docs/ops.md`, "Account deletion page"). **BLOCKING:** set `PRIVACY_CONTACT_EMAIL`, deploy, open the URL, and enter it here. |
| Is the app a Families app (designed for children)? | **No** | Audience is general. |
| Does the app use an SDK that collects data? | **Yes**: Google Mobile Ads SDK, Firebase Authentication, Firebase Crashlytics, Google UMP. | Each one has to be declared. |

## Data types

For each type: collected? shared? required or optional? purpose.

| Play category and type | Collected | Shared (with third parties) | Required or optional | Purposes |
|---|---|---|---|---|
| **Personal info** > Name | Yes | No | Optional (the player chooses a display name) | App functionality (leaderboards), account management |
| **Personal info** > Email address | Yes (only for players who register) | No | Optional | Account management, app functionality |
| **Personal info** > User IDs | Yes (Firebase user ID, every player) | No (confirm: AdMob receives the advertising ID, not the Firebase ID) | Required | App functionality, account management, analytics, fraud prevention |
| **Financial info** | No | No | | The app has no purchases. |
| **Health and fitness**, **Messages**, **Photos and videos**, **Audio files**, **Contacts**, **Calendar**, **Files and docs**, **Web browsing**, **Music and audio** (as data about the user) | No | No | | The app plays licensed songs but collects nothing about the user's own audio. Confirm this reading of "Music and audio". (confirm) |
| **Location** > Approximate location | Yes (country from the IP address, server side; also collected by AdMob) | Yes, AdMob (ads) | Required for the server side. Ads are a separate, Google-collected item. | App functionality (country), advertising or marketing |
| **Location** > Precise location | No | No | | The app does not ask for location permission. |
| **App activity** > App interactions | Yes (sessions: which rounds were played and how) | No | Required | App functionality, analytics, fraud prevention, security |
| **App activity** > In-app search history, installed apps, other user-generated content | No | No | | No search, no installed-app list, no user posts. |
| **App info and performance** > Crash logs | Yes (Crashlytics) | No (Google processes it as the Firebase provider) | Required | Analytics, app functionality (fixing crashes) |
| **App info and performance** > Diagnostics | Yes (Crashlytics: device model, OS version, app version) | No | Required | Analytics |
| **Device or other IDs** > Device or other IDs | Yes (advertising ID, collected by the Google Mobile Ads SDK) | Yes, AdMob | Required by the SDK | Advertising or marketing |
| **Ads** (the Play "Ads" data, where asked) | Yes (ad views and clicks, collected by AdMob) | Yes, AdMob | Required by the SDK | Advertising or marketing |

## Explanations to paste into Play (short form)

- **User IDs:** "A random identifier, created when the game starts, keeps your progress and scores together. Signing in
  links it to your account."
- **App interactions:** "Which songs you answered and how quickly, plus your scores, so leaderboards and cheat checks
  work."
- **Advertising:** "Google's ad SDK collects an advertising ID and ad interactions to show ads. In the EEA, the UK and
  Switzerland, you choose whether ads are personalized."

## Things to check before submitting

- The advertising ID row must be declared even though the app asks for consent. Play compares the manifest's AD_ID
  permission (added by the Google Mobile Ads SDK) with this form. (confirm)
- The country code is derived on the server from `cf.country`, so the answer for location is "Yes, approximate".
- The account deletion web page (Overview) exists and its URL is entered in Play Console > App content > Data safety.
- If a feature adds data later (for example phone sign-in, which is deferred), update this form before the release.
