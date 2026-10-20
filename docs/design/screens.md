# Screens: layout, components, content and behavior

The spec for every screen and state in the approved direction, **F · Adey**. Each section names its board: the HTML in `artifacts/` (exact sizes, colors, spacing) and the screenshot in `screens/` (English and Amharic side by side). Strings are referred to by their `copy.md` key; token names refer to `tokens.json`.

Boards are 840 × 900 and hold two 360 × 780 phones: English on the left, Amharic on the right. Sample data on the boards (player names, scores, pack sizes, `[Song] · [Artist]` rows) is illustrative. The only real song–artist pair used is "Ere Mela Mela" by Mahmoud Ahmed.

## Shared layout

**The hero.** Most screens start with a yellow hero: gradient `color.hero.*` with a white radial glow behind the focal element, bottom corners `radius.hero` (44, 40 on dense screens), shadow `elevation.hero`. The body below starts 12 px higher (`spacing.heroOverlap`), so the curve sits on a cream band (`color.background.heroFade`) that fades to white over 140 px. The Leaderboard and its loading state are yellow from top to bottom instead (`color.hero.fullScreenBottom`).

**Bottom bar** (Home, Settings): white, top corners 36, `elevation.bottomBar`. Three items: Home icon button (52 × 52), the big **Play** button (140 × 62, yellow, icon + `nav.play`), Settings icon button. The current tab's icon button is dark (`color.surface.dark`, yellow icon). Play starts a game straight away with the last-used era, mode and difficulty (shown on Home as `home.quickPlay.label`); the first game uses All eras · Intro · Easy. The leaderboard is not a tab: it opens from a row on Home and from Results.

**Back button**: white 48 × 48 square, radius 16, chevron. Label `nav.back` for screen readers. On the round screen it is labelled `round.leave` and asks for confirmation (`round.leave.*`).

**Buttons**: primary (yellow, min height 58, `elevation.primary`), secondary (white card, 54), text link (underlined, 48 tall). Every raised thing has a press edge; pressing moves it down by the edge height over `motion.duration.press`.

**Cards and rows**: white → cream gradient, radius 16–20, `elevation.card` / `row` / `answer`. Rows are at least 64 tall with a 44 coloured icon tile on the left.

**Selected options** (language, mode, chips): turn dark (`color.surface.dark`), text cream, accents yellow.

**Toggles**: 46 × 28, teal when on (`color.toggle`), `role=switch`.

**Accessibility**: WCAG AA contrast (coral and yellow always carry ink text), 48 dp minimum touch target, text scale up to 1.3 without overflow, every icon-only button has a label, correct/wrong differ by icon and word as well as color, live regions (`role=status`) for feedback, timers and loading.

**Script handling**: in Amharic the phone uses Noto Sans Ethiopic first and line height 1.55 (1.5 on dense screens); numbers and the round counter stay in Poppins.

## 11 · First launch: language — `H01-Language`

- **Layout**: full-height hero with the logo tiles (40 × 40, the `color.logoTiles` sequence), `app.name` and `app.tagline`. Below, on cream: a bilingual prompt (`onboard.lang.title` in both scripts on one line, so it reads before a language is chosen), two option rows (`onboard.lang.amharic`, `onboard.lang.english`, each in its own script) with radio dots, `onboard.lang.later`, primary `common.next`.
- **Default**: preselected from the phone locale (`am` → Amharic, everything else → English). The board shows both cases.
- **Behavior**: the app switches language as soon as an option is tapped. Shown once; afterwards the language lives in Settings.

## 11 · First launch: welcome — `H02-Welcome`

- **Layout**: 400-tall hero with the cassette and two sample answer tiles (Mahmoud Ahmed, Aster Aweke) as a preview of play. Body: `onboard.welcome.title` (display), `onboard.welcome.body`, page dots (2 of 2), primary `onboard.welcome.start`.
- **Behavior**: Start goes straight into round 1 of an All eras · Intro · Easy game from the built-in starter songs. No sign-up, no download, no consent screen before the first round (consent comes after the first finished game, H15).

## 01 · Home — `H03-Home` (online), `H17-OfflineHome` (offline)

- **Hero**: logo tiles (30 × 30), `home.hello` (title), two stat tiles on translucent white: `home.best.label` with the best score (Poppins 22), and `home.quickPlay.label` with what Play will start (`home.quickPlay.settings`, e.g. "The '80s · Intro · Easy").
- **Body**: `home.chooseMode`, then three mode rows (icon tile in the mode's color, `mode.*.name`, `home.mode.*.short`, chevron): Intro (yellow, note icon), Middle (coral, pulse icon), Which Era? (sage, clock icon). Then a dark **Leaderboard** row (yellow trophy tile, `home.leaderboard`, subline `home.leaderboard.guest` for guests or the player's rank when signed in).
- **Bottom bar** with Home selected.
- **States**:
  - *Guest, online* (H03).
  - *Returning, signed in*: Leaderboard subline becomes `results.weeklyRank`.
  - *First run*: best tile shows `home.best.none` instead of a number.
  - *Offline* (H17): a dark banner in the hero (`offline.banner.builtInOnly` when no packs are downloaded, `offline.banner` when some are), Play's subline changes to built-in songs (`home.builtIn` · mode · difficulty), and the Leaderboard subline reads `home.leaderboard.offline`. Rows stay tappable; the leaderboard opens in its offline state.
- **Behavior**: mode rows open Mode select with that mode preselected. There is never a pack or download prompt on Home.

## 02 · Mode select — `H04-ModeSelect`

- **Layout**: hero with back button and `mode.title`. Body: three large option cards (52 icon tile, name, tag, description): Intro (no tag), Middle (`mode.middle.tag` "+25%"), Which Era? (`mode.bonus`). The selected card is dark. Then `mode.guess.label` with a three-item segmented control (`mode.guess.song`, `mode.guess.artist`, and Mixed, `startQuestionsMixed`: each round is a song or an artist question; hidden for Which Era?). Mixed was added in Phase 4 · Sprint 2 so every way to play in the PRD is offered; the Amharic for it is the one the first prototype used, not yet reviewed against the deck. Primary `common.next`.
- **Behavior**: Next opens Era setup. The last choice is remembered and becomes what Play starts. Which Era? plays 10 s of the intro in a 15 s window whatever the setup says, for all eras (`docs/scoring.md`).

## 03 · Era, genre, difficulty — `H05-EraSetup`

- **Layout**: compact hero (back + mode name). Body, top to bottom:
  - `era.title` and a 2-column grid of six era cards, each in its era color (`color.era.*`): All eras, Golden Age (`era.golden.range`), the '80s, the '90s, the 2000s, Modern (`era.modern.range`). Selected = 3 px ink ring.
  - `genre.title` and wrapping chips (`genre.*`), single select, "Any genre" default, selected chip dark.
  - `difficulty.title` and a 3-item segmented control (`difficulty.easy/medium/hard`).
  - Primary `setup.start`.
- **States**: offline, eras with too few songs on the phone are disabled with `era.offlineUnavailable`; a combination with too few songs shows `setup.tooFewSongs` and disables Start.

## 04 · Round — `H06-Round` (clip playing)

- **Hero** (top to bottom): back/leave button, round counter (`round.counter`, Poppins, centered), running score (`round.score`); era chip (era color) and difficulty chip (white); the **cassette** (200 × 128, `color.cassette.*`, the playing indicator, `aria-hidden`; screen readers get `a11y.playing` instead); timer bar (8 tall, `color.timer`) with the seconds pill (`round.secondsLeft`).
- **Body**: the question (`round.question.song` / `.artist` / `.era`, 20 bold, in a `role=status` area 64 tall), the **2 × 2 answer grid** (tiles min 84 tall, 12 gap, `elevation.answer`, label `a11y.answer`), and the hint button at the bottom (lightbulb + `round.hint.button`).
- **Behavior**:
  - The clip plays from the round's start; the reels spin (`motion.duration.reelSpin`) while audio plays and stop when it ends.
  - The timer runs for clip length + 5 s (`docs/scoring.md`). The bar drains left to right; the pill shows whole seconds left. Screen readers hear `a11y.timer` at 10 s and 5 s left, not every second.
  - Tapping an answer locks all tiles and goes to feedback. When the timer runs out: time-out feedback.
  - Backgrounding the app pauses the clip and timer.
  - Interstitial ads appear only **between** rounds: after feedback, before the next clip, every 3 rounds (`timing.interstitialEveryRounds`, from `/v1/config`), never in the player's first session and never while audio plays. Interstitials are mandatory (no skip until the ad allows it). Ad placeholders while an ad loads: `ad.label` badge and `ad.loading`; under the interstitial, `ad.interstitialCaption`.

## 05 · Feedback: correct — `H07-Correct`

- The picked tile turns **correct** (teal gradient, `elevation.answerCorrect`, white text, check icon + `feedback.correct`) with `motion.duration.answerPop`. Other tiles dim to `color.answer.dimOpacity`.
- Heading: `feedback.correct` + points (`feedback.points`), 24, `color.correct.text`. Subline: `feedback.speedBonus`, or `feedback.hintUsed` when a hint was used.
- Score in the hero counts up to the new total. Timer bar freezes.
- Auto-advances after `timing.feedbackCorrect` (1 s).

## 05 · Feedback: wrong / time-out — `H08-Wrong`

- The picked tile turns **wrong** (red gradient, X icon + `feedback.yourPick`); the right tile turns correct (check + `feedback.correct`); the other two dim.
- Heading: `feedback.wrong` (or `feedback.timeout` with no picked tile), 24, `color.wrong.text`. Subline: `feedback.reveal` (song · artist), or `feedback.revealEra` in Which Era?.
- At the bottom: text link `feedback.tapToContinue` with a countdown. Shows for `timing.feedbackWrong` (5 s); a tap anywhere advances early.

## 04 · Round: hint sheet — `H09-Hint`

- Bottom sheet over a scrim (`color.background.scrim`), top corners 32, grabber. Title `round.hint` with a yellow countdown chip (`round.hint.closesIn`, from 8), `round.hint.terms`, an info note with a pause icon (`round.hint.paused`), primary `round.hint.watch`, link `round.hint.cancel`.
- While the sheet is open the timer pill reads `round.timerPaused` and the timer is stopped. The clip keeps playing.
- **Behavior**: closes itself after `timing.hintSheetMax` (8 s), same as No thanks. Watch ad plays a rewarded ad (timer still paused, full-screen ad with `ad.rewardCaption` while it loads); when the ad completes, two wrong tiles fade to `color.answer.removedOpacity`, become untappable, and the hint button is replaced by `feedback.hintUsed`. If the ad is closed early: `ad.notFinished`, no hint. If no ad is available: `ad.unavailable`, sheet closes. One hint per round. The rewarded ad is the player's choice (AdMob policy); interstitials are not.
- Scoring: the round's points are halved; paused time is excluded from `response_ms` (`docs/scoring.md`).
- **Wired in Phase 4 · Sprint 3:** the hint button shows only while a rewarded ad is loaded. Watch ad stops the clip for the ad. Afterwards, rewarded or not, the clip plays again from its start and the timer carries on from where the sheet opened, the same as after a call. The hint can be tried once a round: after No thanks, an ad closed early or no ad, the button does not come back that round. If a call or another app still has the phone when an ad closes, the clip waits for Resume. `ad.notFinished` and `ad.unavailable` show as a short snackbar. The `ad.label` badge has no countdown under a real ad.

**Paused notice** (added in Phase 4 · Sprint 2). When the app comes back from the background, or a call took the audio, the round is stopped (timer pill `round.timerPaused`, reels still) under a centered dialog on the scrim: title `roundPausedTitle`, body `roundPausedBody` (the clip plays again, the time already used still counts) and one primary button `roundResume`. These are production-only strings (see the note on production strings in `copy.md`); the Amharic title is marked `REVIEW`. Resume plays the clip again and the answer window carries on from what was left. It is the same dialog component as "Leave this game?", with no second button. Screenshots: `round-resume-notice-*`.

## 15 · Round: next song loading — `H18-NextSongLoading`

- Rare state from `docs/architecture.md` (play-first delivery): the next round's clip isn't on the phone and no swap is possible.
- Same hero, timer bar full, no seconds pill, reels still. The question area shows `round.loading` and `round.loading.note`; the four answer tiles are shimmering skeletons (`motion.duration.shimmer`); no hint button. `aria-busy`.
- **Behavior**: waits up to `timing.nextSongWaitMax` (10 s). If the clip arrives, the round starts normally. If not, the round is skipped with no penalty and a short toast `feedback.skipped`, then the next round loads.

## 06 · Results — `H10-Results`

- **Hero**: `results.title`, the total (`typography.scale.score`, Poppins 52), `results.correctCount`, and a dark `results.newBest` badge when it's a new best.
- **Body**: for guests a dark row `results.guestRank` (opens the sign-in sheet); for signed-in players `results.weeklyRank`. Then `results.rounds`: one row per round with number, check or X (in correct/wrong color), "song · artist", and points.
- **Actions**: primary `results.playAgain` (same settings), then two secondary buttons side by side: `results.change` and `results.home`.
- **States**: `results.savedOffline` when the session is queued; `results.notRanked` when the server rejects the session. The score shown first is provisional and is replaced by the server's score when the upload returns.
- **Syncing** (added in Phase 4 · Sprint 2): until the server has answered, the note line reads `results.syncing` ("Checking your score…") with a sync icon, under the rank row. When it answers, the total runs up or down to the server's score, and if it differs from the phone's count the same line reads `results.serverDiffers`. The approved board shows no syncing line; the screenshots here show the syncing state, which every results picture is in until the server answers. It shows only while an answer can come: the game is queued, the phone is online with an account, and no send has failed. Offline or without an account the line is `results.savedOffline`; after a failed send while online it is `results.sendLater` with a clock icon; a game that was never queued (the save failed) has no line. "New personal best" is judged again on the server's score.
- **Actions wired**: Play again starts the same settings; "Change era or mode" goes to setup; Home to the start; the rank row opens the leaderboard, or for a guest the register sheet.
- After the first finished game, Ad consent (H15) appears before Results. After the 5th finished game for a guest, the sign-in sheet (H12) appears over Results.

## 07 · Leaderboard — `H11-Leaderboard`, loading `H20-Loading`

- Full-height yellow screen. Header: back + `lb.title`. A segmented control (`lb.weekly`, `lb.allTime`) and an era dropdown chip (`lb.era`).
- **Podium**: top three as colored avatar tiles with names and scores; first place is larger, in coral, with a drawn crown.
- **List**: ranks 4+ on translucent white rows (rank, avatar tile, name, points).
- **Guest**: a white bar pinned to the bottom with `lb.guest.title`, `lb.guest.body` and a small yellow `lb.guest.cta`.
- **Signed in**: the player's own row is pinned at the bottom, highlighted, as `lb.you` with `lb.yourRank`.
- Points use `lb.points`. A signed-in player with no game this week sees `lb.notRanked` in the pinned row.
- **States**: `lb.empty`; offline with a cached board (`lb.offline`); offline with nothing cached (`lb.offline.none`); **loading** (H20): title and `lb.loading` (`role=status`), shimmering podium and seven row skeletons, shown only after `timing.skeletonDelay`.

## 09 · Sign-in sheet (iOS) — `H12-SignIn`

- Bottom sheet over the dimmed Results screen. Trophy tile + `auth.prompt.title`, `auth.prompt.body`, a teal check line `auth.prompt.carryOver`. Buttons: `auth.apple` (black, Apple logo; iOS only; placed first as a design choice, and at least as prominent as the other options, as App Store guideline 4.8 requires), `auth.google` (white), `auth.email` (white, mail icon), link `auth.notNow`.
- Android shows the same sheet without the Apple button.
- **Email**: a follow-up sheet with `auth.email.label`, `auth.password.label`, `auth.email.submit`, `auth.email.create`, `auth.email.forgot`, errors `auth.error.*`. Not drawn in hi-fi; use the same sheet, field and button styles.
- **States**: `auth.signingIn` (buttons disabled, spinner in the pressed one), `auth.signedIn` toast, `auth.linkFailed`.

## 10 · Settings — `H13-Settings`

- **Hero**: `settings.title`, `settings.language` with a two-item segmented control (አማርኛ / English), switches the app language immediately.
- **Body**: a card with two toggles (`settings.sound`, `settings.haptics`); an account row (`settings.guest` + small yellow `settings.signIn`, or, under `settings.account`, the signed-in name with `settings.signOut` and its confirm `settings.signOut.confirm`); rows for `settings.offline` (with an update badge when an installed pack has an update), `settings.adPrivacy` (opens the UMP privacy options form), `settings.privacy`, `settings.about` (which also shows `settings.musicCredit`); `settings.version` at the bottom.
- Bottom bar with Settings selected.
- **Signed in**: also `settings.delete` (confirm dialog with `settings.delete.body` / `.confirm`).

## 08 · Settings › Offline play — `H14-OfflinePlay`, error `H19-DownloadError`

- **Hero**: back + `packs.title`, `packs.intro`.
- **Body**:
  - A card with two toggles: `packs.wifiOnly` (on by default), and `packs.mobilePrefetch` (on by default) with `packs.mobilePrefetch.help`. Off is the data saver from the architecture doc.
  - Section `packs.onPhone`, with the cache size and its cap (`packs.cacheOfCap`) and a small `packs.clearCache` button on the same line, then the storage the songs use by source (`packs.storageUsed`). Rows: Built-in songs (`packs.builtIn`, `packs.builtIn.meta`, `packs.always`; can't be removed), then each downloaded pack (`packs.downloaded` with a check; long-press or swipe for `packs.remove`).
  - Section `packs.available`: pack rows with art tile in the era color, name, `packs.songs` · `packs.size`, and a small yellow `packs.download` button.
- **Pack row states**: not installed (Download), downloading (progress bar `packs.progress` in the meta line, X button `packs.cancel`), verifying (`packs.verifying`), installed, update available (`packs.updateAvailable`, button `packs.update`), remove confirm (`packs.remove.confirm`), cellular confirm (`packs.mobileData.*`) when Download is tapped on mobile data while Wi-Fi only is on, not enough storage (`packs.storageFull`), offline (`packs.offline`).
- **Download failed** (H19): the row becomes an inline error card (`color.surface.errorCard`) with a warning icon, `error.download` in `color.text.error`, and a small `error.retry` button. A corrupt download (`error.packCorrupt`) retries by itself.
- The list scrolls; the last row may be cut off at the bottom, as on the boards.

## 12 · Ad consent — `H15-AdConsent`

- Message-screen template: 360-tall hero with a 120 × 120 icon badge (coral, heart), then title, body, and buttons.
- Content: `consent.title`, `consent.body`, primary `consent.continue`, which opens Google's UMP consent form (and on iOS, the ATT prompt after it).
- **When**: after the first finished game, before Results; only where UMP says consent is required. Never before the first round.

## 13 · Forced update — `H16-ForcedUpdate`

- Same template, white badge with a download icon. `update.title`, `update.body`, primary `update.cta.android` / `update.cta.ios` (opens the store), secondary `update.playOffline` (plays built-in and downloaded songs; no network features).
- **When**: `/v1/config` reports a minimum version above the installed one.

## 14 · Offline: out of songs — `H21-OutOfSongs`

- Same template, lavender badge with a repeat icon. `empty.outOfSongs.title`, `empty.outOfSongs.body`, primary `empty.outOfSongs.packs` (opens Settings › Offline play), secondary `empty.outOfSongs.replay` (starts a game that allows recently played songs).
- **When**: offline, and every clip on the phone was played recently, so a session can't be built from unplayed songs.

## Error and loading patterns without their own board

- **Generic error**: message-screen template with `error.generic.title`, `error.generic.body`, primary `error.retry`.
- **Sync**: `error.sync` and `offline.pending` / `offline.synced` as toasts.
- **Skeletons**: shimmering placeholder shapes in the layout of the content they replace (see H20); shown only after `timing.skeletonDelay`. The Offline play pack list uses the same pattern (row-shaped skeletons).
- **App start**: `loading.app` under the logo tiles on the yellow hero. Anything else short uses `loading.generic`.
- **Offline toast**: `offline.banner.short` when the connection drops mid-session.
- **Leave game**: dialog with `round.leave.title`, `round.leave.body`, `round.leave.confirm`, `round.leave.cancel`.

## ▶ Round prototype — `P00-RoundPrototype`

An interactive version of the round for judging pacing: open it on the canvas and press Play, or read its logic class. It runs 5 rounds with a 15 s window and implements the timings above: 1 s correct feedback, 5 s wrong feedback with tap to skip, the 8 s hint sheet with the timer paused, a 3 s fake rewarded ad that removes 2 answers and halves points, a 2.5 s fake interstitial after round 3, and a results screen. Differences from the spec, because it is a demo: it shows an interstitial in what would be the first session, it reveals only the artist on a wrong answer (`feedback.reveal` shows song · artist), and its "right" answers are arbitrary.
