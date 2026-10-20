# Privacy policy: Yeman Zefen (የማን ዘፈን)

> **DRAFT. A lawyer must review this before it is published.** Items in `[square brackets]` are placeholders
> to fill in. Items marked **(confirm)** describe a vendor or a legal position that has to be checked against
> current vendor terms and the applicable law before publishing.

Last updated: [date of publication]

## 1. Who we are

Yeman Zefen is a free, ad-supported music-guessing game for Amharic music. It is published by
[legal name of the developer], [postal address], [country].

Contact for privacy questions and requests: **[privacy contact email]**. We aim to answer within 30 days.

The app is not designed for children, and we do not knowingly collect data from anyone under [13, or the
minimum age for your jurisdictions, confirm]. If you think a child has given us information, contact us and we
will delete it.

## 2. What we collect and why

| Data | When it is collected | Purpose | Who processes it |
|---|---|---|---|
| **Firebase user ID** (a random identifier) | Every player. The app signs you in anonymously on first launch. | Keeps your game history, leaderboard position and account together. | Google (Firebase Authentication) and us |
| **Email address** | Only if you create an account with email, or sign in with Google or Apple and share your email. | Signing in, account recovery. Not shown to other players. | Google (Firebase Authentication) |
| **Display name** | Only if you choose one. | Shown on the leaderboards once you have a registered account. | Us (stored on our servers) |
| **Sign-in provider** (Google, email, Apple) | When you sign in. | Signing you back in. | Google (Firebase), Apple (for Sign in with Apple) |
| **Country** (from your IP address) | Each request to our servers. We store the two-letter country code, not the address. | Country-level statistics, and shown next to your display name on the leaderboards. | Cloudflare (which derives it), and us |
| **Game sessions**: the tracks you were asked about, your answers, response times, scores, game mode and difficulty, whether it was played offline, and ad views | When you finish a game. Sessions played offline are sent when you are back online. | Scoring, leaderboards, anti-cheating checks, and the usage reports described in section 6. | Us |
| **Moderation records**: anti-cheating flags on sessions, whether a player is hidden from others' leaderboards, and our administrators' notes on those decisions | When a session looks implausible, or an administrator reviews a player. | Keeping leaderboards fair. | Us |
| **Clip problem reports**: the track and the kind of error, if a clip will not play | Automatically, when a clip fails to play on your phone. | Fixing broken audio. | Us |
| **Crash reports and diagnostics**: the crash stack, device model, operating system version, app version, and your Firebase user ID (never your email) | When the app crashes or a handled error is logged. Only in the released app. | Finding and fixing crashes. | Google (Firebase Crashlytics) and us |
| **Advertising ID** (Android advertising ID or Apple's IDFA), ad requests and clicks, approximate location from your IP address, and device information | When ads are shown. | Showing ads, and in regions that require it, personalized ads. | Google (AdMob, Google Mobile Ads SDK) |
| **Consent choices** for ads, and Apple's tracking choice | When you answer the consent form or the iOS tracking prompt. | Showing ads lawfully. | Google (UMP) and Apple, and us (the answer, not the form) |

**Stored only on your device.** Starter clips, downloaded clip cache, offline packs, your local best scores and the
queue of sessions waiting to upload are kept on your phone. They are removed when you delete the app or your
account (section 5). We do not receive them unless they are uploaded as a session.

**What we do not collect.** We do not collect your phone number, your precise location, your contacts, your photos,
or the content of your messages. The app has no chat between players.

## 3. Who we share data with

We share data only with the service providers below, to run the app. We do not sell personal data.

- **Google (Firebase Authentication and Crashlytics; Google Mobile Ads and the User Messaging Platform, for AdMob).**
  Google acts as our processor for Firebase, and as an independent controller for the ad data that AdMob collects
  through its SDK. (confirm)
- **Apple**, for Sign in with Apple, if you choose it.
- **Cloudflare**, which hosts our servers, database and audio files, and sees your IP address to serve requests.
- **Music association.** We report how often each track is played, for royalty payments. These reports count plays
  per track and per day, and do not include your account, email or device identifiers. (confirm the form of
  reporting in the licence agreement)

Some of these providers are in countries outside yours, including the United States. Where that transfer needs
safeguards under your law, they rely on the providers' standard contractual clauses or equivalent mechanism.
(confirm)

## 4. Advertising and consent

Ads are shown by Google AdMob. In the European Economic Area, the United Kingdom and Switzerland, Google asks for
your consent before personalized ads are shown, through its consent form. You can change your choice at any time in
**Settings > Ad privacy choices**, where that option is shown in those regions.

On iPhone, Apple asks whether the app may track you across other companies' apps and websites. If you say no, the
app does not send your advertising identifier for tracking. You can change this in your iPhone's settings.

Elsewhere, no consent form is shown and ads may be personalized using your advertising ID. You can turn off
personalized ads in your device's settings (Android: Settings > Google > Ads, delete or reset the advertising ID;
iPhone: Settings > Privacy & Security > Tracking). On iPhone, ads are personalized only if you allowed tracking.
(confirm, including whether a US state privacy message is needed)

## 5. How long we keep data, and deleting it

- **Account and game data** are kept while your account exists.
- **Game sessions:** after 90 days, the detail of each round (the question, the options shown, the answer you chose,
  how long you took and whether you used a hint) is removed. What remains is the session summary: the mode,
  difficulty, score, country, the tracks played, and for each round its points and whether it was correct. This is
  kept as long as your account is, and after that as described below.
- **Deleting your account.** In the app, go to **Settings > Account > Delete account**. This:
  - removes your display name and your leaderboard rows;
  - unlinks your game sessions from you: they are kept, with no user ID, display name or email attached, because
    the play counts reported to the music association (section 3) and our usage totals (section 6) are built from
    them;
  - deletes your sign-in account from Firebase;
  - revokes the app's access to your Apple account, if you signed in with Apple.
  Deletion is immediate on our servers. Our database keeps a point-in-time history for restores (Cloudflare D1
  Time Travel), so deleted data leaves it within [7 days on the Free plan, 30 days on the Paid plan, confirm].
- **Moderation records** about a player (section 2) are kept after the account is deleted, still under the deleted
  account's user ID, as a record of the decisions made. They are kept for [retention period, confirm].
- **Crash reports** are kept by Google for [number of days, confirm Crashlytics retention].
- **Ad data** is kept by Google under its own policies. (confirm)
- **Rate-limit counters** that stop abuse are kept for about one day.
- **Server logs:** our own log line for each request records the route, the response status, the time taken, the
  country, and a one-way hash of your user ID, and never your email. Cloudflare's logging may also record request
  details such as your IP address. (confirm from a production log entry) They are kept for [number of days, confirm
  Workers Logs retention].

If you cannot delete your account in the app, email us at the contact address in section 1.

## 6. Usage reports

We count daily totals, such as the number of players, sessions and rounds, and the number of plays per track and per
country. These totals do not identify anyone. We use them to choose music, understand the audience and report to
the music association.

## 7. Security

Connections to our servers use HTTPS. Requests that change your data are checked against your sign-in token. Admin
access to our data is restricted to named administrators, and their actions are logged. No system is perfectly
secure. If we learn of a breach that affects your data, we will tell you as the law requires.

## 8. Your rights

Depending on where you live, you may have the right to:

- **access** the personal data we hold about you;
- **correct** it;
- **delete** it (section 5);
- **restrict or object** to some processing;
- **receive** a copy of it in a common format;
- **withdraw consent** for ads at any time (section 4).

To use these rights, contact us at **[privacy contact email]**. We may need to confirm who you are before we act.

If you are in the European Economic Area or the United Kingdom and you think we have not handled your data properly,
you can complain to your local data protection authority. (confirm the list of authorities and the lead authority
for the business)

## 9. Changes to this policy

If we change this policy, we will update the date above, and for significant changes we will show a notice in the app.

## 10. Language

This policy is written in English. [አማርኛ: an Amharic version will be published at the same address. Until it is,
the English text applies.] (Native-speaker review required before the Amharic version is published.)

---

### Amharic version: structure

The sections above keep the same numbers in the Amharic version. Translate the headings and the table column names
first, then the body text, and have a native speaker check it against the English before publishing.

| # | English heading | አማርኛ |
|---|---|---|
| 1 | Who we are | [ማን ነን] |
| 2 | What we collect and why | [የምንሰበስበው መረጃ እና ለምን] |
| 3 | Who we share data with | [መረጃ የምናጋራው ማንን ጋር ነው] |
| 4 | Advertising and consent | [ማስታወቂያ እና ፈቃድ] |
| 5 | How long we keep data, and deleting it | [መረጃን የምንይዝበት ጊዜ እና መሰረዝ] |
| 6 | Usage reports | [የአጠቃቀም ሪፖርቶች] |
| 7 | Security | [ደህንነት] |
| 8 | Your rights | [መብቶችዎ] |
| 9 | Changes to this policy | [ፖሊሲው ሲቀየር] |
| 10 | Language | [ቋንቋ] |
