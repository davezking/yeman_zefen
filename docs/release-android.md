# Releasing the Android app

A tag push builds a signed, obfuscated prod AAB in GitHub Actions (`.github/workflows/app-android.yml`) and keeps it as a run artifact. Play's first upload is by hand; after that, a repository variable turns on uploads to the internal track.

```
# 1. Set the version in app/pubspec.yaml (name only: the +N is ignored, CI sets the build number), merge it.
# 2. Tag the merge commit and push the tag:
git tag app-v0.2.0 && git push origin app-v0.2.0
```

The tag's version (a `-rc1` suffix is allowed) must equal the name in `pubspec.yaml`, or the run fails at the first step. **The version has one source: `pubspec.yaml`.** The build number (Android `versionCode`) is the workflow's run number plus the optional repository variable `ANDROID_BUILD_NUMBER_OFFSET`, so it only goes up. Play rejects a `versionCode` it has seen: if you ever upload a build made elsewhere, set the offset above it.

The run refuses to build while `app/config/prod.json` has a placeholder `API_BASE` (still `https://api.TODO-set-domain`) or real ad units with Google's sample AdMob app id (`app/tool/check_release_config.sh`).

## One-time setup

### 1. The upload key

Play App Signing is on for new apps: Google holds the key that signs what users install, and you sign uploads with an **upload key**. Create it once, on your own machine:

```
keytool -genkeypair -v -keystore upload-keystore.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

- Choose a long random store password (the key password can be the same). Put the file **and** both passwords in your password manager, and keep a second copy of the file somewhere offline (an encrypted USB stick). Never commit it: `*.jks`, `*.keystore` and `key.properties` are gitignored.
- If the upload key is lost, Play support can reset it (Play holds the real signing key), but that takes days. Back it up anyway.
- Print its fingerprint and keep it: `keytool -list -v -keystore upload-keystore.jks -alias upload`. Every run's summary shows the signing certificate's SHA-256; it must match this one.

### 2. Secrets

Create a GitHub **environment** named `release` (Settings > Environments), add yourself as a required reviewer, and under **Deployment branches and tags** allow only tags matching `app-v*`. Every release then waits for your approval, and only a release tag's run of this job can read the secrets. Add these **environment secrets**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` (on a Mac: `base64 -i upload-keystore.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | the key password |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | a service account key (JSON) of the Firebase project `yeman-zefen` that may upload Crashlytics symbols (Google Cloud > IAM > Service accounts; a Crashlytics role, or Firebase Admin if unsure). The JSON is secret: it can be revoked in the console |
| `PLAY_SERVICE_ACCOUNT_JSON` | only for the Play upload below |

The workflow writes the keystore and `android/key.properties` into the runner's temp directory, checks the passwords and alias with `keytool` before building, and deletes both at the end, even when the build fails.

### 3. Crashlytics symbols

The build is obfuscated (`--obfuscate --split-debug-info`), so a crash report is unreadable without its symbols. The run uploads the Dart symbols to Crashlytics with the Firebase CLI, and the Crashlytics Gradle plugin uploads the R8 mapping during the build. It also keeps both as artifacts (`symbols.zip`, `mapping.txt`) for 90 days. If a Crashlytics upload fails the run fails; re-run it, or upload by hand with `firebase crashlytics:symbols:upload --app=<APP_ID> <dir>`.

### 4. Play Console

1. Create the app in Play Console. Keep **Play App Signing** on.
2. Download the AAB from the first tag run (Actions > the run > Artifacts) and upload it by hand to Testing > **Internal testing**. Play needs the first release made in the console; the store listing, content rating, data safety form and the app-access/ads declarations must be filled in before a release can roll out (`docs/store-compliance.md` when it exists).
3. In Play Console > App integrity > App signing, compare the **upload key certificate** SHA-256 with the one in the run summary.
4. Add the **Play signing** SHA-1 (App integrity > App signing > App signing key certificate) and the upload key's SHA-1 to the Android app in Firebase. Google sign-in on Android fails in a Play build without it (`docs/ops.md`).
5. Add yourself to the internal testers list and install from the opt-in link.

### 5. Automatic uploads to the internal track (optional)

After the first manual upload: create a service account in Google Cloud, invite it in Play Console (Users and permissions) with permission to release to testing tracks, put its JSON key in `PLAY_SERVICE_ACCOUNT_JSON`, and set the repository variable `PLAY_UPLOAD` to `true`. The step uses a third-party action (`r0adkll/upload-google-play`); pin it to a commit before relying on it, because it sees the service account.

## Checks before the first release

- A tag push produces an AAB, and the run summary's certificate fingerprint matches Play Console's upload certificate.
- The AAB installs from the internal track, and a forced crash on that build shows up in Crashlytics with readable Dart and Java frames.
- `docs/ops.md` > Ads: the real AdMob app ids and ad units are in place.
