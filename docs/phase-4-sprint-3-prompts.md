# Phase 4 · Sprint 3 — Account settings & ads

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: account management, and ads that respect consent rules and never interrupt a clip. After this sprint the app is feature-complete.

---

## Task: Account settings, sign-out, and account deletion

**Model:** sonnet — deletion and re-authentication have failure paths that must leave the player in a valid state.

**Context:** The register sheet, display-name step, and leaderboard went live in Phase 3 from the prototype screens. The settings account section (guest and registered variants) exists from Phase 2 and was wired for display in Sprint 1. `AuthService` and `DELETE /v1/me` exist. Apple and Google require in-app account deletion, and Firebase may require recent sign-in before deleting a user.

**Do this:**
1. Account section actions: show linked provider(s); sign out (becomes a fresh guest, with the designed warning that leaderboard rank needs sign-in); and **Delete account** with the designed two-step confirm. If Firebase reports `requires-recent-login`, re-authenticate with the same provider, then retry. After deletion, the user is a new guest.
2. Polish the auth error messaging from real-world testing: wrong password, network failure, cancelled sign-in, and the conflict-merge confirmation ("progress combined").

**Before moving on, check:**
- Every provider path works on both platforms, including cancel.
- Account deletion works end to end, and the user disappears from the leaderboard.

---

## Task: AdMob — consent, ATT, interstitials, rewarded hint

**Model:** sonnet — ads involve consent and platform rules where mistakes cause store rejections or policy strikes.

**Context:** FR-19: interstitials no more often than every N rounds (`/v1/config`, default 3), **never during a clip**, plus rewarded ads that grant a hint (remove 2 wrong options; the round's points are halved per `docs/scoring.md`, and the event already carries `hintUsed`). EU and UK diaspora users need consent via Google's UMP SDK before personalized ads. iOS needs an App Tracking Transparency prompt. Ad counts go into the session payload's `ads` object. Use test ad unit IDs in the dev flavor.

**Do this:**
1. `lib/core/ads/`:
   - `ConsentService`: run the UMP flow on startup before any ad request. Add a "privacy options" entry in settings when UMP requires it. On iOS, show the ATT prompt after UMP, per Google's recommended order.
   - `AdService`: preload one interstitial and one rewarded ad, reloading after each show.
   - `AdPolicy`: decides interstitial timing. Show only **between rounds, after feedback, before the next clip starts**, and only once the round count since the last interstitial is ≥ N. Never in the first session, and never during a clip.
2. Rewarded hint: a hint button on the round screen, shown only while a rewarded ad is loaded. It pauses the clip and timer, shows the ad, and on `onUserEarnedReward` removes 2 wrong options and sets `hintUsed = true`, then resumes. If the ad is closed early, nothing changes and the timer resumes.
3. Count `interstitialShown` and `rewardedCompleted` into the session payload.
4. Add `app-ads.txt` hosting instructions to `docs/ops.md`. Put ad unit IDs and AdMob app IDs per flavor in configuration, not in code.

**Before moving on, check:**
- With test ads, no interstitial ever appears while audio is playing (play 3 full sessions).
- A rewarded hint correctly halves that round's points on both client and server.
- With the device region set to an EU country, the consent form appears before any ad loads.
