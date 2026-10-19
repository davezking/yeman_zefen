# Design review and sign-off (M1)

The review of the Flutter prototype against the approved designs. It is the last step of Phase 2: when the checklist below is complete, the design is signed off and Phase 3 can start. Tick a box (☐ → ☑) when it is true, and keep the notes next to it.

- **What is reviewed:** the Flutter screens in `app/lib/prototype/screens/`, running on mock data (nothing here is wired to a service).
- **Against:** the approved boards in [`artifacts/`](artifacts/) (HTML) and [`screens/`](screens/) (pictures), specified in [`screens.md`](screens.md), with the words in [`copy.md`](copy.md).
- **Screenshots:** [the gallery below](#3-screenshot-gallery) shows every screen and state in English and Amharic. They are drawn by the app's own tests with the real fonts, so Fidel is real Fidel, and they are checked in CI: a screen cannot change without its screenshot changing too.

## 1. Try the prototype

**Android.** In GitHub, open *Actions → prototype → Run workflow*, then download the `prototype-android` artifact from the finished run and install the APK (allow "install unknown apps" for the browser or Files app). It installs as **Yeman Zefen DEV**, next to any real build. To build it yourself: `cd app && flutter build apk --release --flavor dev -t lib/main_prototype.dart`.

**iPhone.** From a Mac with Xcode, with your Apple ID as the signing team (see `app/README.md`): `cd app && flutter run -d <your iPhone> --release --flavor dev -t lib/main_prototype.dart`. (A TestFlight build needs the Apple developer account from Phase 5; until then this is the way.)

**What to try.** Every screen is reachable by tapping, starting from a first launch: language → welcome → a game → results → register; Home → mode → era → a game; Settings (language, sounds, Offline play with a pack download, sign out, delete account); the leaderboard from Home and from Results. The states that need a special situation (offline, forced update, out of songs, a failed download, ad consent) are reached from the **hidden dev menu**: put **three fingers on the screen at once**. It switches guest / registered, online / offline and `en` / `am`, and jumps to any screen or state. Do not show it to test players.

## 2. Sign-off checklist

### 2.1 Every PRD key screen, in both languages

The key screens of the PRD (§ M1). For each, compare the screenshots in the gallery (and, on the phone, the real thing) with the approved board, in both languages: layout, spacing, colour, copy, and that nothing is clipped or overflows.

| PRD key screen | Boards | English | Amharic |
|---|---|---|---|
| Home / landing | H03, H17 | ☐ | ☐ |
| Game-mode select (intro / middle) | H04 | ☐ | ☐ |
| Era and genre select | H05 | ☐ | ☐ |
| The round (clip playing, timer, answers) | H06, H09, H18 | ☐ | ☐ |
| Correct / wrong feedback | H07, H08 | ☐ | ☐ |
| Round results and score | H10 | ☐ | ☐ |
| Leaderboard | H11, H20 | ☐ | ☐ |
| Pack browse and download | H14, H19 | ☐ | ☐ |
| Sign-in / register prompt | H12 | ☐ | ☐ |
| Settings with the Amharic ↔ English toggle | H13 | ☐ | ☐ |
| First launch, ad consent, forced update, out of songs | H01, H02, H15, H16, H21 | ☐ | ☐ |

Already checked by CI, on every change: every screen and state fits a 360 dp phone in both languages at text scale 1.0 and 1.3 without overflow (`app/test/prototype/screens_layout_test.dart`); every screenshot is pixel-identical to what the code draws (`app/test/design/`); the strings in the app are the strings in `copy.md`, in both languages (`app/test/prototype/prototype_guards_test.dart`).

### 2.2 Native-speaker Amharic review

☐ Every Amharic string in [`copy.md`](copy.md) has been reviewed by a native speaker. (Its header says so; the strings added in Sprint 2 were each reviewed when they were added.)

☐ The Amharic **screenshots** were read as a whole, not only the strings: line breaks, nothing cut off, numbers and Latin names mixed with Fidel, the Fidel line height, and the two scripts side by side on the leaderboard and results.

- Reviewer: ____________________  Date: ____________
- Notes:

### 2.3 Test with real players

3 to 5 target players, a mix of **domestic** (in Ethiopia) and **diaspora**, from Telegram or Facebook music groups. Give each the prototype on their own phone (or yours), say nothing about how it works, and watch the first minutes. Ask them to: play a first game; change the era and play again; look at the leaderboard; find where to switch the language; find where to download songs for offline play. Then ask what they expected, what they would change, and whether they would play again.

| # | Who (domestic / diaspora, age range) | Phone and OS | Language | Date | Finished a game unaided? | Found Offline play? | Notes |
|---|---|---|---|---|---|---|---|
| 1 | | | | | ☐ | ☐ | |
| 2 | | | | | ☐ | ☐ | |
| 3 | | | | | ☐ | ☐ | |
| 4 | | | | | ☐ | ☐ | |
| 5 | | | | | ☐ | ☐ | |

☐ At least 3 players tried it, with both domestic and diaspora among them.

Findings that need a design change (each goes through a PR, see section 4):

-

### 2.4 Accessibility

| Check | How | Done |
|---|---|---|
| Nothing overflows at text scale 1.3, in both languages | CI (`screens_layout_test.dart`) | ☑ |
| Buttons are at least 48 dp | CI (`components_test.dart`, `app_theme_test.dart`) | ☑ |
| Correct and wrong differ by icon and word, not colour alone | In the code and the screenshots: a check and "Correct", an X and "Your pick" | ☑ |
| Reduced motion replaces movement with fades | CI (`round_flow_test.dart`, "reduced motion"); also try the phone's "Remove animations" / "Reduce Motion" setting | ☐ |
| Text contrast is at least WCAG AA (coral and yellow carry dark text) | Measure the colour pairs in the screenshots with a contrast checker | ☐ |
| Correct and wrong are told apart in greyscale | Desaturate a round screenshot. Known: the teal and red tiles come out nearly the same grey, so the icon and the word carry it | ☐ |
| Every control has a spoken label, and the order makes sense | Go through Home, a round and Settings with TalkBack (Android) and VoiceOver (iPhone) | ☐ |
| The system text size at the largest setting still works | Phone settings → font size, then open Home, a round, Results, Settings | ☐ |

Notes:

### 2.5 Approval

Decision (tick one): ☐ Approved  ☐ Approved with the changes listed above  ☐ Not approved

I approve this design as the basis for Phase 3 and Phase 4.

Approved by: ____________________  Date: ____________

## 3. Screenshot gallery

Each state is shown in English and Amharic on the design's 360 × 780 phone (click an image for the full size), with links to the 430 × 932 pictures. The approved board above each table shows English on the left and Amharic on the right. Sample data on the boards (names, scores) differs from the prototype's mock data; layout, colour and copy are what to compare. This part is generated: do not edit between the markers, run `app/tool/export_screens.sh`.

<!-- gallery:begin (generated by app/tool/export_screens.sh) -->

### H01 · Language

[Approved board (HTML)](artifacts/H01-Language.dc.html) · English left, Amharic right:

<img src="screens/H01-Language.webp" width="420" alt="Approved board H01 · Language">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| first launch: language, English<br>`language-english` | <img src="flutter/language-english-en-360x780.png" width="180" alt="first launch: language, English, en"> | <img src="flutter/language-english-am-360x780.png" width="180" alt="first launch: language, English, am"> | [English](flutter/language-english-en-430x932.png) · [Amharic](flutter/language-english-am-430x932.png) |
| first launch: language, Amharic<br>`language-amharic` | <img src="flutter/language-amharic-en-360x780.png" width="180" alt="first launch: language, Amharic, en"> | <img src="flutter/language-amharic-am-360x780.png" width="180" alt="first launch: language, Amharic, am"> | [English](flutter/language-amharic-en-430x932.png) · [Amharic](flutter/language-amharic-am-430x932.png) |

### H02 · Welcome

[Approved board (HTML)](artifacts/H02-Welcome.dc.html) · English left, Amharic right:

<img src="screens/H02-Welcome.webp" width="420" alt="Approved board H02 · Welcome">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| first launch: welcome<br>`welcome` | <img src="flutter/welcome-en-360x780.png" width="180" alt="first launch: welcome, en"> | <img src="flutter/welcome-am-360x780.png" width="180" alt="first launch: welcome, am"> | [English](flutter/welcome-en-430x932.png) · [Amharic](flutter/welcome-am-430x932.png) |

### H03 · Home

[Approved board (HTML)](artifacts/H03-Home.dc.html) · English left, Amharic right:

<img src="screens/H03-Home.webp" width="420" alt="Approved board H03 · Home">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| home, guest online<br>`home-guest-online` | <img src="flutter/home-guest-online-en-360x780.png" width="180" alt="home, guest online, en"> | <img src="flutter/home-guest-online-am-360x780.png" width="180" alt="home, guest online, am"> | [English](flutter/home-guest-online-en-430x932.png) · [Amharic](flutter/home-guest-online-am-430x932.png) |
| home, first run<br>`home-first-run` | <img src="flutter/home-first-run-en-360x780.png" width="180" alt="home, first run, en"> | <img src="flutter/home-first-run-am-360x780.png" width="180" alt="home, first run, am"> | [English](flutter/home-first-run-en-430x932.png) · [Amharic](flutter/home-first-run-am-430x932.png) |
| home, signed in<br>`home-signed-in` | <img src="flutter/home-signed-in-en-360x780.png" width="180" alt="home, signed in, en"> | <img src="flutter/home-signed-in-am-360x780.png" width="180" alt="home, signed in, am"> | [English](flutter/home-signed-in-en-430x932.png) · [Amharic](flutter/home-signed-in-am-430x932.png) |

### H04 · Mode select

[Approved board (HTML)](artifacts/H04-ModeSelect.dc.html) · English left, Amharic right:

<img src="screens/H04-ModeSelect.webp" width="420" alt="Approved board H04 · Mode select">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| mode select, intro<br>`mode-select-intro` | <img src="flutter/mode-select-intro-en-360x780.png" width="180" alt="mode select, intro, en"> | <img src="flutter/mode-select-intro-am-360x780.png" width="180" alt="mode select, intro, am"> | [English](flutter/mode-select-intro-en-430x932.png) · [Amharic](flutter/mode-select-intro-am-430x932.png) |
| mode select, middle<br>`mode-select-middle` | <img src="flutter/mode-select-middle-en-360x780.png" width="180" alt="mode select, middle, en"> | <img src="flutter/mode-select-middle-am-360x780.png" width="180" alt="mode select, middle, am"> | [English](flutter/mode-select-middle-en-430x932.png) · [Amharic](flutter/mode-select-middle-am-430x932.png) |
| mode select, which era<br>`mode-select-which-era` | <img src="flutter/mode-select-which-era-en-360x780.png" width="180" alt="mode select, which era, en"> | <img src="flutter/mode-select-which-era-am-360x780.png" width="180" alt="mode select, which era, am"> | [English](flutter/mode-select-which-era-en-430x932.png) · [Amharic](flutter/mode-select-which-era-am-430x932.png) |

### H05 · Era setup

[Approved board (HTML)](artifacts/H05-EraSetup.dc.html) · English left, Amharic right:

<img src="screens/H05-EraSetup.webp" width="420" alt="Approved board H05 · Era setup">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| setup<br>`setup` | <img src="flutter/setup-en-360x780.png" width="180" alt="setup, en"> | <img src="flutter/setup-am-360x780.png" width="180" alt="setup, am"> | [English](flutter/setup-en-430x932.png) · [Amharic](flutter/setup-am-430x932.png) |
| setup, offline eras disabled<br>`setup-offline-eras-disabled` | <img src="flutter/setup-offline-eras-disabled-en-360x780.png" width="180" alt="setup, offline eras disabled, en"> | <img src="flutter/setup-offline-eras-disabled-am-360x780.png" width="180" alt="setup, offline eras disabled, am"> | [English](flutter/setup-offline-eras-disabled-en-430x932.png) · [Amharic](flutter/setup-offline-eras-disabled-am-430x932.png) |
| setup, too few songs<br>`setup-too-few-songs` | <img src="flutter/setup-too-few-songs-en-360x780.png" width="180" alt="setup, too few songs, en"> | <img src="flutter/setup-too-few-songs-am-360x780.png" width="180" alt="setup, too few songs, am"> | [English](flutter/setup-too-few-songs-en-430x932.png) · [Amharic](flutter/setup-too-few-songs-am-430x932.png) |

### H06 · Round

[Approved board (HTML)](artifacts/H06-Round.dc.html) · English left, Amharic right:

<img src="screens/H06-Round.webp" width="420" alt="Approved board H06 · Round">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| round: clip playing<br>`round-clip-playing` | <img src="flutter/round-clip-playing-en-360x780.png" width="180" alt="round: clip playing, en"> | <img src="flutter/round-clip-playing-am-360x780.png" width="180" alt="round: clip playing, am"> | [English](flutter/round-clip-playing-en-430x932.png) · [Amharic](flutter/round-clip-playing-am-430x932.png) |
| round: clip ended, still answering<br>`round-clip-ended` | <img src="flutter/round-clip-ended-en-360x780.png" width="180" alt="round: clip ended, still answering, en"> | <img src="flutter/round-clip-ended-am-360x780.png" width="180" alt="round: clip ended, still answering, am"> | [English](flutter/round-clip-ended-en-430x932.png) · [Amharic](flutter/round-clip-ended-am-430x932.png) |
| round: Which Era?<br>`round-which-era` | <img src="flutter/round-which-era-en-360x780.png" width="180" alt="round: Which Era?, en"> | <img src="flutter/round-which-era-am-360x780.png" width="180" alt="round: Which Era?, am"> | [English](flutter/round-which-era-en-430x932.png) · [Amharic](flutter/round-which-era-am-430x932.png) |
| round: hint available<br>`round-hint-available` | <img src="flutter/round-hint-available-en-360x780.png" width="180" alt="round: hint available, en"> | <img src="flutter/round-hint-available-am-360x780.png" width="180" alt="round: hint available, am"> | [English](flutter/round-hint-available-en-430x932.png) · [Amharic](flutter/round-hint-available-am-430x932.png) |

### H07 · Correct

[Approved board (HTML)](artifacts/H07-Correct.dc.html) · English left, Amharic right:

<img src="screens/H07-Correct.webp" width="420" alt="Approved board H07 · Correct">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| round: right<br>`round-correct` | <img src="flutter/round-correct-en-360x780.png" width="180" alt="round: right, en"> | <img src="flutter/round-correct-am-360x780.png" width="180" alt="round: right, am"> | [English](flutter/round-correct-en-430x932.png) · [Amharic](flutter/round-correct-am-430x932.png) |
| round: right with the hint<br>`round-correct-with-hint` | <img src="flutter/round-correct-with-hint-en-360x780.png" width="180" alt="round: right with the hint, en"> | <img src="flutter/round-correct-with-hint-am-360x780.png" width="180" alt="round: right with the hint, am"> | [English](flutter/round-correct-with-hint-en-430x932.png) · [Amharic](flutter/round-correct-with-hint-am-430x932.png) |

### H08 · Wrong

[Approved board (HTML)](artifacts/H08-Wrong.dc.html) · English left, Amharic right:

<img src="screens/H08-Wrong.webp" width="420" alt="Approved board H08 · Wrong">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| round: wrong<br>`round-wrong` | <img src="flutter/round-wrong-en-360x780.png" width="180" alt="round: wrong, en"> | <img src="flutter/round-wrong-am-360x780.png" width="180" alt="round: wrong, am"> | [English](flutter/round-wrong-en-430x932.png) · [Amharic](flutter/round-wrong-am-430x932.png) |
| round: wrong in Which Era?<br>`round-wrong-which-era` | <img src="flutter/round-wrong-which-era-en-360x780.png" width="180" alt="round: wrong in Which Era?, en"> | <img src="flutter/round-wrong-which-era-am-360x780.png" width="180" alt="round: wrong in Which Era?, am"> | [English](flutter/round-wrong-which-era-en-430x932.png) · [Amharic](flutter/round-wrong-which-era-am-430x932.png) |
| round: time-out<br>`round-timeout` | <img src="flutter/round-timeout-en-360x780.png" width="180" alt="round: time-out, en"> | <img src="flutter/round-timeout-am-360x780.png" width="180" alt="round: time-out, am"> | [English](flutter/round-timeout-en-430x932.png) · [Amharic](flutter/round-timeout-am-430x932.png) |

### H09 · Hint

[Approved board (HTML)](artifacts/H09-Hint.dc.html) · English left, Amharic right:

<img src="screens/H09-Hint.webp" width="420" alt="Approved board H09 · Hint">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| round: hint applied<br>`round-hint-applied` | <img src="flutter/round-hint-applied-en-360x780.png" width="180" alt="round: hint applied, en"> | <img src="flutter/round-hint-applied-am-360x780.png" width="180" alt="round: hint applied, am"> | [English](flutter/round-hint-applied-en-430x932.png) · [Amharic](flutter/round-hint-applied-am-430x932.png) |
| round: hint sheet<br>`round-hint-sheet` | <img src="flutter/round-hint-sheet-en-360x780.png" width="180" alt="round: hint sheet, en"> | <img src="flutter/round-hint-sheet-am-360x780.png" width="180" alt="round: hint sheet, am"> | [English](flutter/round-hint-sheet-en-430x932.png) · [Amharic](flutter/round-hint-sheet-am-430x932.png) |
| round: rewarded ad<br>`round-rewarded-ad` | <img src="flutter/round-rewarded-ad-en-360x780.png" width="180" alt="round: rewarded ad, en"> | <img src="flutter/round-rewarded-ad-am-360x780.png" width="180" alt="round: rewarded ad, am"> | [English](flutter/round-rewarded-ad-en-430x932.png) · [Amharic](flutter/round-rewarded-ad-am-430x932.png) |

### H10 · Results

[Approved board (HTML)](artifacts/H10-Results.dc.html) · English left, Amharic right:

<img src="screens/H10-Results.webp" width="420" alt="Approved board H10 · Results">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| results: guest, new best<br>`results-guest-new-best` | <img src="flutter/results-guest-new-best-en-360x780.png" width="180" alt="results: guest, new best, en"> | <img src="flutter/results-guest-new-best-am-360x780.png" width="180" alt="results: guest, new best, am"> | [English](flutter/results-guest-new-best-en-430x932.png) · [Amharic](flutter/results-guest-new-best-am-430x932.png) |
| results: signed in<br>`results-signed-in` | <img src="flutter/results-signed-in-en-360x780.png" width="180" alt="results: signed in, en"> | <img src="flutter/results-signed-in-am-360x780.png" width="180" alt="results: signed in, am"> | [English](flutter/results-signed-in-en-430x932.png) · [Amharic](flutter/results-signed-in-am-430x932.png) |
| results: saved offline<br>`results-saved-offline` | <img src="flutter/results-saved-offline-en-360x780.png" width="180" alt="results: saved offline, en"> | <img src="flutter/results-saved-offline-am-360x780.png" width="180" alt="results: saved offline, am"> | [English](flutter/results-saved-offline-en-430x932.png) · [Amharic](flutter/results-saved-offline-am-430x932.png) |
| results: not counted<br>`results-not-counted` | <img src="flutter/results-not-counted-en-360x780.png" width="180" alt="results: not counted, en"> | <img src="flutter/results-not-counted-am-360x780.png" width="180" alt="results: not counted, am"> | [English](flutter/results-not-counted-en-430x932.png) · [Amharic](flutter/results-not-counted-am-430x932.png) |
| results: synced<br>`results-synced` | <img src="flutter/results-synced-en-360x780.png" width="180" alt="results: synced, en"> | <img src="flutter/results-synced-am-360x780.png" width="180" alt="results: synced, am"> | [English](flutter/results-synced-en-430x932.png) · [Amharic](flutter/results-synced-am-430x932.png) |
| results: a big score<br>`results-big-score` | <img src="flutter/results-big-score-en-360x780.png" width="180" alt="results: a big score, en"> | <img src="flutter/results-big-score-am-360x780.png" width="180" alt="results: a big score, am"> | [English](flutter/results-big-score-en-430x932.png) · [Amharic](flutter/results-big-score-am-430x932.png) |

### H11 · Leaderboard

[Approved board (HTML)](artifacts/H11-Leaderboard.dc.html) · English left, Amharic right:

<img src="screens/H11-Leaderboard.webp" width="420" alt="Approved board H11 · Leaderboard">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| leaderboard: guest<br>`leaderboard-guest` | <img src="flutter/leaderboard-guest-en-360x780.png" width="180" alt="leaderboard: guest, en"> | <img src="flutter/leaderboard-guest-am-360x780.png" width="180" alt="leaderboard: guest, am"> | [English](flutter/leaderboard-guest-en-430x932.png) · [Amharic](flutter/leaderboard-guest-am-430x932.png) |
| leaderboard: signed in<br>`leaderboard-signed-in` | <img src="flutter/leaderboard-signed-in-en-360x780.png" width="180" alt="leaderboard: signed in, en"> | <img src="flutter/leaderboard-signed-in-am-360x780.png" width="180" alt="leaderboard: signed in, am"> | [English](flutter/leaderboard-signed-in-en-430x932.png) · [Amharic](flutter/leaderboard-signed-in-am-430x932.png) |
| leaderboard: signed in, not ranked<br>`leaderboard-not-ranked` | <img src="flutter/leaderboard-not-ranked-en-360x780.png" width="180" alt="leaderboard: signed in, not ranked, en"> | <img src="flutter/leaderboard-not-ranked-am-360x780.png" width="180" alt="leaderboard: signed in, not ranked, am"> | [English](flutter/leaderboard-not-ranked-en-430x932.png) · [Amharic](flutter/leaderboard-not-ranked-am-430x932.png) |
| leaderboard: all time, one era<br>`leaderboard-all-time-era` | <img src="flutter/leaderboard-all-time-era-en-360x780.png" width="180" alt="leaderboard: all time, one era, en"> | <img src="flutter/leaderboard-all-time-era-am-360x780.png" width="180" alt="leaderboard: all time, one era, am"> | [English](flutter/leaderboard-all-time-era-en-430x932.png) · [Amharic](flutter/leaderboard-all-time-era-am-430x932.png) |
| leaderboard: empty<br>`leaderboard-empty` | <img src="flutter/leaderboard-empty-en-360x780.png" width="180" alt="leaderboard: empty, en"> | <img src="flutter/leaderboard-empty-am-360x780.png" width="180" alt="leaderboard: empty, am"> | [English](flutter/leaderboard-empty-en-430x932.png) · [Amharic](flutter/leaderboard-empty-am-430x932.png) |
| leaderboard: offline, saved copy<br>`leaderboard-offline-saved` | <img src="flutter/leaderboard-offline-saved-en-360x780.png" width="180" alt="leaderboard: offline, saved copy, en"> | <img src="flutter/leaderboard-offline-saved-am-360x780.png" width="180" alt="leaderboard: offline, saved copy, am"> | [English](flutter/leaderboard-offline-saved-en-430x932.png) · [Amharic](flutter/leaderboard-offline-saved-am-430x932.png) |
| leaderboard: offline, nothing saved<br>`leaderboard-offline-none` | <img src="flutter/leaderboard-offline-none-en-360x780.png" width="180" alt="leaderboard: offline, nothing saved, en"> | <img src="flutter/leaderboard-offline-none-am-360x780.png" width="180" alt="leaderboard: offline, nothing saved, am"> | [English](flutter/leaderboard-offline-none-en-430x932.png) · [Amharic](flutter/leaderboard-offline-none-am-430x932.png) |

### H12 · Sign in

[Approved board (HTML)](artifacts/H12-SignIn.dc.html) · English left, Amharic right:

<img src="screens/H12-SignIn.webp" width="420" alt="Approved board H12 · Sign in">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| sign in: iOS<br>`sign-in-ios` | <img src="flutter/sign-in-ios-en-360x780.png" width="180" alt="sign in: iOS, en"> | <img src="flutter/sign-in-ios-am-360x780.png" width="180" alt="sign in: iOS, am"> | [English](flutter/sign-in-ios-en-430x932.png) · [Amharic](flutter/sign-in-ios-am-430x932.png) |
| sign in: Android<br>`sign-in-android` | <img src="flutter/sign-in-android-en-360x780.png" width="180" alt="sign in: Android, en"> | <img src="flutter/sign-in-android-am-360x780.png" width="180" alt="sign in: Android, am"> | [English](flutter/sign-in-android-en-430x932.png) · [Amharic](flutter/sign-in-android-am-430x932.png) |
| sign in: signing in<br>`sign-in-signing-in` | <img src="flutter/sign-in-signing-in-en-360x780.png" width="180" alt="sign in: signing in, en"> | <img src="flutter/sign-in-signing-in-am-360x780.png" width="180" alt="sign in: signing in, am"> | [English](flutter/sign-in-signing-in-en-430x932.png) · [Amharic](flutter/sign-in-signing-in-am-430x932.png) |
| sign in: could not link<br>`sign-in-link-failed` | <img src="flutter/sign-in-link-failed-en-360x780.png" width="180" alt="sign in: could not link, en"> | <img src="flutter/sign-in-link-failed-am-360x780.png" width="180" alt="sign in: could not link, am"> | [English](flutter/sign-in-link-failed-en-430x932.png) · [Amharic](flutter/sign-in-link-failed-am-430x932.png) |
| email: sign in<br>`email-sign-in` | <img src="flutter/email-sign-in-en-360x780.png" width="180" alt="email: sign in, en"> | <img src="flutter/email-sign-in-am-360x780.png" width="180" alt="email: sign in, am"> | [English](flutter/email-sign-in-en-430x932.png) · [Amharic](flutter/email-sign-in-am-430x932.png) |
| email: bad address<br>`email-bad-address` | <img src="flutter/email-bad-address-en-360x780.png" width="180" alt="email: bad address, en"> | <img src="flutter/email-bad-address-am-360x780.png" width="180" alt="email: bad address, am"> | [English](flutter/email-bad-address-en-430x932.png) · [Amharic](flutter/email-bad-address-am-430x932.png) |
| email: wrong password<br>`email-wrong-password` | <img src="flutter/email-wrong-password-en-360x780.png" width="180" alt="email: wrong password, en"> | <img src="flutter/email-wrong-password-am-360x780.png" width="180" alt="email: wrong password, am"> | [English](flutter/email-wrong-password-en-430x932.png) · [Amharic](flutter/email-wrong-password-am-430x932.png) |
| email: create an account<br>`email-create-account` | <img src="flutter/email-create-account-en-360x780.png" width="180" alt="email: create an account, en"> | <img src="flutter/email-create-account-am-360x780.png" width="180" alt="email: create an account, am"> | [English](flutter/email-create-account-en-430x932.png) · [Amharic](flutter/email-create-account-am-430x932.png) |
| email: signing in<br>`email-signing-in` | <img src="flutter/email-signing-in-en-360x780.png" width="180" alt="email: signing in, en"> | <img src="flutter/email-signing-in-am-360x780.png" width="180" alt="email: signing in, am"> | [English](flutter/email-signing-in-en-430x932.png) · [Amharic](flutter/email-signing-in-am-430x932.png) |

### H13 · Settings

[Approved board (HTML)](artifacts/H13-Settings.dc.html) · English left, Amharic right:

<img src="screens/H13-Settings.webp" width="420" alt="Approved board H13 · Settings">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| settings, guest<br>`settings-guest` | <img src="flutter/settings-guest-en-360x780.png" width="180" alt="settings, guest, en"> | <img src="flutter/settings-guest-am-360x780.png" width="180" alt="settings, guest, am"> | [English](flutter/settings-guest-en-430x932.png) · [Amharic](flutter/settings-guest-am-430x932.png) |
| settings, signed in<br>`settings-signed-in` | <img src="flutter/settings-signed-in-en-360x780.png" width="180" alt="settings, signed in, en"> | <img src="flutter/settings-signed-in-am-360x780.png" width="180" alt="settings, signed in, am"> | [English](flutter/settings-signed-in-en-430x932.png) · [Amharic](flutter/settings-signed-in-am-430x932.png) |
| settings, update badge<br>`settings-update-badge` | <img src="flutter/settings-update-badge-en-360x780.png" width="180" alt="settings, update badge, en"> | <img src="flutter/settings-update-badge-am-360x780.png" width="180" alt="settings, update badge, am"> | [English](flutter/settings-update-badge-en-430x932.png) · [Amharic](flutter/settings-update-badge-am-430x932.png) |

### H14 · Offline play

[Approved board (HTML)](artifacts/H14-OfflinePlay.dc.html) · English left, Amharic right:

<img src="screens/H14-OfflinePlay.webp" width="420" alt="Approved board H14 · Offline play">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| offline play, all states<br>`offline-play-all-states` | <img src="flutter/offline-play-all-states-en-360x780.png" width="180" alt="offline play, all states, en"> | <img src="flutter/offline-play-all-states-am-360x780.png" width="180" alt="offline play, all states, am"> | [English](flutter/offline-play-all-states-en-430x932.png) · [Amharic](flutter/offline-play-all-states-am-430x932.png) |
| offline play, offline<br>`offline-play-offline` | <img src="flutter/offline-play-offline-en-360x780.png" width="180" alt="offline play, offline, en"> | <img src="flutter/offline-play-offline-am-360x780.png" width="180" alt="offline play, offline, am"> | [English](flutter/offline-play-offline-en-430x932.png) · [Amharic](flutter/offline-play-offline-am-430x932.png) |
| offline play, verifying<br>`offline-play-verifying` | <img src="flutter/offline-play-verifying-en-360x780.png" width="180" alt="offline play, verifying, en"> | <img src="flutter/offline-play-verifying-am-360x780.png" width="180" alt="offline play, verifying, am"> | [English](flutter/offline-play-verifying-en-430x932.png) · [Amharic](flutter/offline-play-verifying-am-430x932.png) |

### H15 · Ad consent

[Approved board (HTML)](artifacts/H15-AdConsent.dc.html) · English left, Amharic right:

<img src="screens/H15-AdConsent.webp" width="420" alt="Approved board H15 · Ad consent">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| ad consent<br>`ad-consent` | <img src="flutter/ad-consent-en-360x780.png" width="180" alt="ad consent, en"> | <img src="flutter/ad-consent-am-360x780.png" width="180" alt="ad consent, am"> | [English](flutter/ad-consent-en-430x932.png) · [Amharic](flutter/ad-consent-am-430x932.png) |
| ad consent: Google's form<br>`ad-consent-google-form` | <img src="flutter/ad-consent-google-form-en-360x780.png" width="180" alt="ad consent: Google's form, en"> | <img src="flutter/ad-consent-google-form-am-360x780.png" width="180" alt="ad consent: Google's form, am"> | [English](flutter/ad-consent-google-form-en-430x932.png) · [Amharic](flutter/ad-consent-google-form-am-430x932.png) |

### H16 · Forced update

[Approved board (HTML)](artifacts/H16-ForcedUpdate.dc.html) · English left, Amharic right:

<img src="screens/H16-ForcedUpdate.webp" width="420" alt="Approved board H16 · Forced update">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| forced update, Android<br>`forced-update-android` | <img src="flutter/forced-update-android-en-360x780.png" width="180" alt="forced update, Android, en"> | <img src="flutter/forced-update-android-am-360x780.png" width="180" alt="forced update, Android, am"> | [English](flutter/forced-update-android-en-430x932.png) · [Amharic](flutter/forced-update-android-am-430x932.png) |
| forced update, iOS<br>`forced-update-ios` | <img src="flutter/forced-update-ios-en-360x780.png" width="180" alt="forced update, iOS, en"> | <img src="flutter/forced-update-ios-am-360x780.png" width="180" alt="forced update, iOS, am"> | [English](flutter/forced-update-ios-en-430x932.png) · [Amharic](flutter/forced-update-ios-am-430x932.png) |

### H17 · Offline home

[Approved board (HTML)](artifacts/H17-OfflineHome.dc.html) · English left, Amharic right:

<img src="screens/H17-OfflineHome.webp" width="420" alt="Approved board H17 · Offline home">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| home, offline with no packs<br>`home-offline-no-packs` | <img src="flutter/home-offline-no-packs-en-360x780.png" width="180" alt="home, offline with no packs, en"> | <img src="flutter/home-offline-no-packs-am-360x780.png" width="180" alt="home, offline with no packs, am"> | [English](flutter/home-offline-no-packs-en-430x932.png) · [Amharic](flutter/home-offline-no-packs-am-430x932.png) |
| home, offline with packs<br>`home-offline-with-packs` | <img src="flutter/home-offline-with-packs-en-360x780.png" width="180" alt="home, offline with packs, en"> | <img src="flutter/home-offline-with-packs-am-360x780.png" width="180" alt="home, offline with packs, am"> | [English](flutter/home-offline-with-packs-en-430x932.png) · [Amharic](flutter/home-offline-with-packs-am-430x932.png) |

### H18 · Next song loading

[Approved board (HTML)](artifacts/H18-NextSongLoading.dc.html) · English left, Amharic right:

<img src="screens/H18-NextSongLoading.webp" width="420" alt="Approved board H18 · Next song loading">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| round: next song loading<br>`round-next-song-loading` | <img src="flutter/round-next-song-loading-en-360x780.png" width="180" alt="round: next song loading, en"> | <img src="flutter/round-next-song-loading-am-360x780.png" width="180" alt="round: next song loading, am"> | [English](flutter/round-next-song-loading-en-430x932.png) · [Amharic](flutter/round-next-song-loading-am-430x932.png) |

### H19 · Download error

[Approved board (HTML)](artifacts/H19-DownloadError.dc.html) · English left, Amharic right:

<img src="screens/H19-DownloadError.webp" width="420" alt="Approved board H19 · Download error">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| offline play, download failed<br>`offline-play-download-failed` | <img src="flutter/offline-play-download-failed-en-360x780.png" width="180" alt="offline play, download failed, en"> | <img src="flutter/offline-play-download-failed-am-360x780.png" width="180" alt="offline play, download failed, am"> | [English](flutter/offline-play-download-failed-en-430x932.png) · [Amharic](flutter/offline-play-download-failed-am-430x932.png) |
| offline play, corrupt<br>`offline-play-corrupt` | <img src="flutter/offline-play-corrupt-en-360x780.png" width="180" alt="offline play, corrupt, en"> | <img src="flutter/offline-play-corrupt-am-360x780.png" width="180" alt="offline play, corrupt, am"> | [English](flutter/offline-play-corrupt-en-430x932.png) · [Amharic](flutter/offline-play-corrupt-am-430x932.png) |
| offline play, storage full<br>`offline-play-storage-full` | <img src="flutter/offline-play-storage-full-en-360x780.png" width="180" alt="offline play, storage full, en"> | <img src="flutter/offline-play-storage-full-am-360x780.png" width="180" alt="offline play, storage full, am"> | [English](flutter/offline-play-storage-full-en-430x932.png) · [Amharic](flutter/offline-play-storage-full-am-430x932.png) |

### H20 · Loading

[Approved board (HTML)](artifacts/H20-Loading.dc.html) · English left, Amharic right:

<img src="screens/H20-Loading.webp" width="420" alt="Approved board H20 · Loading">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| leaderboard: loading<br>`leaderboard-loading` | <img src="flutter/leaderboard-loading-en-360x780.png" width="180" alt="leaderboard: loading, en"> | <img src="flutter/leaderboard-loading-am-360x780.png" width="180" alt="leaderboard: loading, am"> | [English](flutter/leaderboard-loading-en-430x932.png) · [Amharic](flutter/leaderboard-loading-am-430x932.png) |

### H21 · Out of songs

[Approved board (HTML)](artifacts/H21-OutOfSongs.dc.html) · English left, Amharic right:

<img src="screens/H21-OutOfSongs.webp" width="420" alt="Approved board H21 · Out of songs">

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| out of songs<br>`out-of-songs` | <img src="flutter/out-of-songs-en-360x780.png" width="180" alt="out of songs, en"> | <img src="flutter/out-of-songs-am-360x780.png" width="180" alt="out of songs, am"> | [English](flutter/out-of-songs-en-430x932.png) · [Amharic](flutter/out-of-songs-am-430x932.png) |

### No approved board

States the boards do not draw. They are specified in [`screens.md`](screens.md) ("Error and loading patterns" and the sections of the screens they belong to).

| State | English | Amharic | Larger phone (430×932) |
|---|---|---|---|
| app start<br>`app-start` | <img src="flutter/app-start-en-360x780.png" width="180" alt="app start, en"> | <img src="flutter/app-start-am-360x780.png" width="180" alt="app start, am"> | [English](flutter/app-start-en-430x932.png) · [Amharic](flutter/app-start-am-430x932.png) |
| generic error<br>`error-generic` | <img src="flutter/error-generic-en-360x780.png" width="180" alt="generic error, en"> | <img src="flutter/error-generic-am-360x780.png" width="180" alt="generic error, am"> | [English](flutter/error-generic-en-430x932.png) · [Amharic](flutter/error-generic-am-430x932.png) |
| offline play: packs loading<br>`offline-play-loading` | <img src="flutter/offline-play-loading-en-360x780.png" width="180" alt="offline play: packs loading, en"> | <img src="flutter/offline-play-loading-am-360x780.png" width="180" alt="offline play: packs loading, am"> | [English](flutter/offline-play-loading-en-430x932.png) · [Amharic](flutter/offline-play-loading-am-430x932.png) |
| round: ad between rounds<br>`round-interstitial-ad` | <img src="flutter/round-interstitial-ad-en-360x780.png" width="180" alt="round: ad between rounds, en"> | <img src="flutter/round-interstitial-ad-am-360x780.png" width="180" alt="round: ad between rounds, am"> | [English](flutter/round-interstitial-ad-en-430x932.png) · [Amharic](flutter/round-interstitial-ad-am-430x932.png) |
| round: leave dialog<br>`round-leave-dialog` | <img src="flutter/round-leave-dialog-en-360x780.png" width="180" alt="round: leave dialog, en"> | <img src="flutter/round-leave-dialog-am-360x780.png" width="180" alt="round: leave dialog, am"> | [English](flutter/round-leave-dialog-en-430x932.png) · [Amharic](flutter/round-leave-dialog-am-430x932.png) |
| round: paused in the background<br>`round-paused` | <img src="flutter/round-paused-en-360x780.png" width="180" alt="round: paused in the background, en"> | <img src="flutter/round-paused-am-360x780.png" width="180" alt="round: paused in the background, am"> | [English](flutter/round-paused-en-430x932.png) · [Amharic](flutter/round-paused-am-430x932.png) |
| round: paused notice with Resume (back from the background or a call)<br>`round-resume-notice` | <img src="flutter/round-resume-notice-en-360x780.png" width="180" alt="round: paused notice with Resume (back from the background or a call), en"> | <img src="flutter/round-resume-notice-am-360x780.png" width="180" alt="round: paused notice with Resume (back from the background or a call), am"> | [English](flutter/round-resume-notice-en-430x932.png) · [Amharic](flutter/round-resume-notice-am-430x932.png) |
| display name<br>`display-name` | <img src="flutter/display-name-en-360x780.png" width="180" alt="display name, en"> | <img src="flutter/display-name-am-360x780.png" width="180" alt="display name, am"> | [English](flutter/display-name-en-430x932.png) · [Amharic](flutter/display-name-am-430x932.png) |
| display name: too short<br>`display-name-too-short` | <img src="flutter/display-name-too-short-en-360x780.png" width="180" alt="display name: too short, en"> | <img src="flutter/display-name-too-short-am-360x780.png" width="180" alt="display name: too short, am"> | [English](flutter/display-name-too-short-en-430x932.png) · [Amharic](flutter/display-name-too-short-am-430x932.png) |
| display name: taken<br>`display-name-taken` | <img src="flutter/display-name-taken-en-360x780.png" width="180" alt="display name: taken, en"> | <img src="flutter/display-name-taken-am-360x780.png" width="180" alt="display name: taken, am"> | [English](flutter/display-name-taken-en-430x932.png) · [Amharic](flutter/display-name-taken-am-430x932.png) |

<!-- gallery:end -->

## 4. After sign-off

Design changes after this point go through a PR that changes the prototype screens **and** re-exports the screenshots (`app/tool/export_screens.sh`), so the design and the code never drift apart. The golden tests fail on a PR that changes a screen but not its screenshot. Changes to what a screen looks like also update [`screens.md`](screens.md), and new or changed Amharic goes to a native speaker first ([`copy.md`](copy.md)).
