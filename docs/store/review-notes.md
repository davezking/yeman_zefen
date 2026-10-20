# Review notes for Apple and Google

Paste into App Store Connect > App Review Information > Notes, and into Play Console > App content > App access
and the release notes for reviewers. Keep the test-account credentials in the store's own fields, not in this
repository.

---

**BLOCKING before submission:** the music licence proof below must be attached or its text pasted. Apple may
ask for it, and the app's catalog cannot be published without it.

## About the app

Yeman Zefen is a free "guess the song" game for Amharic music. Each round plays a short clip (3, 5 or 10 seconds)
and the player picks the song or artist from four options. The game is free and ad-supported (interstitial and
rewarded ads from Google AdMob).

## Music licence

The songs in the game are licensed from [name of the Ethiopian music association] for use in this app. The licence
letter is attached: **[ATTACH: licence letter, PDF, with the date and the signatory's name and title. BLOCKING]**.

Only short clips and titles/artist names are used. Clips can be played from the app and cached on the device.
Users cannot download full songs.

## Reaching the gameplay without an account

No account is needed to play. Open the app and tap play: the first round starts from clips bundled with the app,
so it works without network. Players can sign in later from Settings > Account, or after a finished game, and the
prompt can be dismissed.

Network access is needed for leaderboards, packs and the sync of finished games. Offline play needs packs downloaded
from Settings > Offline play.

## Features that need an account

- **Leaderboards:** only signed-in players appear on them. Guests can view them.
- **Display name:** shown on the leaderboards, with the player's country.
- **Account deletion:** Settings > Account > Delete account.

**Test account (registered features):**
- Email: **[TEST ACCOUNT EMAIL]**
- Password: **[provided in the store's review-notes field, not here]**

To test Sign in with Apple (iOS), use any Apple ID. To test Google sign-in, use any Google account.

## Display names (user-generated content)

The only text players write that others can see is the display name on the leaderboards. There is no chat,
messaging or upload.

- Names are checked on the server against a blocklist of offensive words, and refused if they match.
- Administrators review flagged players and can hide a player from every other player's leaderboard (shadow ban),
  with each decision logged.
- **[Blocking for Apple guideline 1.2 if the reviewer asks: a way for players to report an offensive name. If one is
  added, describe it here. The Amharic part of the blocklist still needs a native speaker's review.]**

## Ads and consent

- Ads come from Google AdMob.
- Interstitial ads appear between rounds, after the first session, and never during audio playback.
- In the EEA, UK and Switzerland, Google's consent form appears after a finished game. Elsewhere it does not.
- On iOS, the App Tracking Transparency prompt appears after a finished game, once the consent check is done.
  Declining it does not stop the game.

## Permissions

The app asks for no location, contacts, camera, microphone or photos permission. On iOS it asks for tracking
permission (above). It needs the network.

## Privacy

- Privacy policy: **[PUBLIC PRIVACY POLICY URL]**
- The in-app Settings > Privacy row opens the same policy. **[confirm the row is wired to the URL in the release build]**
- Account deletion removes the account (see the policy, section 5). Play's web deletion page:
  **[ACCOUNT DELETION URL. BLOCKING for Play]**

## Contact

For questions during review: **[REVIEWER CONTACT EMAIL]**.
