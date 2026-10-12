# Yeman Zefen — Amharic Music Guessing Game — PRD (Final)

**Status:** Final (v1)
**Author:** [you]
**Last updated:** 2026-10-12

> _(assumption: working product name "Yeman Zefen" — የማን ዘፈን, "whose song?" — chosen because it fits the guess-the-artist mechanic. Rename freely.)_

---

## 1. Problem Statement & Background

Music-guessing games (guess the intro, name the artist) are a proven, popular casual-game genre in English-speaking markets (SongPop, Beat the Intro). No equivalent exists for Amharic / Ethiopian music, despite a large domestic audience and a nostalgic, higher-spending diaspora in the US, Europe, Israel, and the Gulf.

The gap is not demand — it's that nobody has solved the two hard problems at once: (1) assembling a clean, correctly-tagged Amharic music catalog (transliteration is inconsistent, metadata is scattered across YouTube and fan sites), and (2) using the recordings legally. This product targets both: a curated catalog built via a scraping/ingestion pipeline, played under a royalty license obtained from the Ethiopian music association.

The app is free and ad-supported, ships on **both Android and iOS** (one Flutter codebase), and is designed for low-bandwidth conditions (downloadable offline song packs rather than always-streaming). Android dominates the domestic market; iOS matters for the diaspora, who skew toward iPhone and are the more ad-valuable audience.

## 2. Goals & Success Metrics

Primary goal: become the default Amharic music game for both domestic and diaspora Ethiopian users, with enough engaged daily players to make ad revenue and sponsorships viable.

_(assumption: the user did not specify targets; the metrics below are proposed starting points.)_

| Metric | Why it matters | Starting target (v1) |
|---|---|---|
| Installs (Android + iOS) | Reach / top-of-funnel | 10,000 in first 3 months |
| D1 / D7 / D30 retention | Is the game actually fun & sticky | 35% / 15% / 6% |
| Daily active users (DAU) | Core engagement | 1,000 DAU by month 3 |
| Avg. rounds per session | Depth of play | ≥ 15 |
| Guest → registered conversion | Soft-gate is working | Track; no target v1 |
| % plays from diaspora geos | Revenue is diaspora-weighted | Track |

Non-goals for this metric set: revenue targets (too early), paid-conversion metrics (no paid tier in v1).

## 3. User Stories / Personas

**Primary — Casual domestic player (Addis, on Android, limited data):**
- As a new user, I want to start playing immediately without signing up, so that nothing blocks me from trying the game.
- As a hooked player, I want to register after a few rounds, so that I can save my scores and join the leaderboard — but only when I choose to.
- As a player, I want to download a song pack once over Wi-Fi, so that I can play offline without burning mobile data.
- As a player, I want to hear a short intro clip and guess the song or artist, so that I feel the nostalgia and challenge.
- As a player, I want to pick a generation/era, so that I can play music I actually grew up with.

**Primary — Diaspora player (nostalgic, often on iPhone, better connectivity, willing to engage):**
- As a diaspora user, I want to compete on a global leaderboard, so that I can measure myself against other Ethiopians worldwide.
- As a diaspora user, I want the UI in English or Amharic, so that I (or my kids) can navigate comfortably.

**Secondary — Competitive player:**
- As a competitive player, I want harder modes (shorter clips, guess-from-the-middle), so that the game stays challenging.

**Admin — Catalog manager:**
- As an admin, I want to run the scraper and review/correct track metadata, so that the catalog is accurate before it reaches players.
- As an admin, I want a review queue of auto-transliterated and flagged entries, so that I can verify them in one place.
- As an admin, I want to set the clip start-time per song, so that clips land on the recognizable part.
- As an admin, I want to export a usage/royalty report, so that I can pay the music association correctly.

## 4. Scope & Non-Goals

**In scope (v1):**
- Flutter app for **Android and iOS** (phone, Amharic + English toggle)
- Guest play by default (no registration to start); optional accounts + online global leaderboards (registration soft-prompted after a few plays, required only to rank)
- Two game modes: **Guess the Intro** and **Guess from the Middle**
- Music categorized by **generation/era** (both as a filter and as a game dimension)
- Downloadable, offline-capable song packs
- Ad monetization (AdMob)
- Backend API + database + object storage for clips
- Admin dashboard: catalog management, scraper control, transliteration review queue, clip editing, pack building, moderation, analytics, royalty usage export
- Ingestion pipeline: ethiozeima scraper (built) + clip cutter (built), extensible to YouTube/Spotify metadata

**Out of scope (v1), with reason:**
- Real-time head-to-head multiplayer — complex; async challenges can come in v2
- Paid / premium tier or in-app purchases — free+ads is the chosen model
- Lyrics-based modes ("finish the lyric") — depends on lyric rights; v2
- Social feed / user-generated content / chat — moderation burden
- Web or desktop client

## 5. Requirements

### Functional Requirements

**Catalog & content**
- **FR-1** The system SHALL store each track with: Amharic title, Latin title, Amharic artist, Latin artist, album, release year, generation/era, source URL, audio reference, and clip start-time(s).
- **FR-2** The system SHALL treat the Amharic (Fidel) artist name as the canonical key and store Latin/transliteration variants as aliases, to deduplicate the same artist across spellings.
- **FR-3** The system SHALL assign each track to exactly one generation/era (see generations taxonomy under Technical Requirements) and SHALL allow an admin to override the auto-assigned value.
- **FR-4** The system SHALL deduplicate tracks (covers, live versions, re-uploads) to one canonical playable clip per song, flagging suspected duplicates for admin review.

**Game modes**
- **FR-5** In **Guess the Intro**, the system SHALL play an audio clip beginning at the track's `clip_start_time` for a configurable length (default 10s) and SHALL ask the user to identify the song and/or artist.
- **FR-6** In **Guess from the Middle**, the system SHALL play a clip beginning at a mid-song timestamp and SHALL present the same guess interaction.
- **FR-7** The system SHALL support difficulty via clip length (e.g., 3s hard / 5s medium / 10s easy) derived from the same start point.
- **FR-8** The system SHALL offer answers as multiple-choice (4 options) in v1, with distractors drawn from the same generation/era to keep difficulty fair.
- **FR-9** The system SHALL award points based on correctness and speed, and SHALL support a "watch a rewarded ad for a hint / extra guess" option.
- **FR-10** The system SHALL log every clip play to the royalty usage log (exported via FR-22).

**Generations / categories**
- **FR-11** The system SHALL let the player choose a generation/era and/or genre before a round, and SHALL support an "all" mix.
- **FR-12** The system SHALL support a bonus mode where the player guesses which generation a song belongs to.

**Accounts, scores, leaderboards**
- **FR-13** The app SHALL be fully playable **without registration** (guest mode): a first-time user can start playing immediately, with scores and progress stored locally on the device. After a configurable number of plays (default: 5 sessions), the system SHALL prompt the guest to register — via Firebase Auth (Google/email) — to save progress and join the leaderboard. The prompt SHALL be dismissible, and registration SHALL stay optional except where a feature requires it (see FR-14). On registration, locally-stored guest scores SHALL migrate to the new account.
- **FR-14** The system SHALL maintain global leaderboards (all-time and weekly), filterable by generation. Guests MAY view leaderboards but SHALL NOT appear on them; **ranking requires a registered account**. Registered users SHALL see their own rank.
- **FR-15** The system SHALL allow offline play with local score capture, syncing to the server when connectivity returns.

**Packs & delivery**
- **FR-16** The system SHALL deliver clips as downloadable packs (grouped by generation/genre), each with a manifest (version, track list, checksums).
- **FR-17** The app SHALL cache downloaded packs for offline play and SHALL notify users when a new/updated pack is available.

**Localization & ads**
- **FR-18** The app SHALL provide a full UI in both Amharic and English with a user-switchable toggle, defaulting from device locale, and SHALL bundle a Fidel-complete font (Noto Sans Ethiopic).
- **FR-19** The app SHALL display ads via AdMob — interstitials spaced no more often than every few rounds (configurable, default every 4) plus optional rewarded ads — without an ad interrupting mid-clip.

**Admin**
- **FR-20** The admin dashboard SHALL let an admin trigger/schedule the scraper, review ingested metadata, edit any field, set clip start-times, and approve tracks before they go live. It SHALL present a **review queue** of auto-transliterated and flagged/duplicate entries (see R-2) so the admin can verify or correct them in one place.
- **FR-21** The admin dashboard SHALL let an admin build and version packs and publish them to object storage.
- **FR-22** The admin dashboard SHALL export a royalty usage report (per-track play counts over a date range) for the music association.
- **FR-23** The admin dashboard SHALL surface core analytics (DAU, installs, retention, rounds/session, ad metrics, plays by geo).

### Technical Requirements

**Recommended stack (free-to-operate at launch):**

| Layer | Choice | Why |
|---|---|---|
| Mobile | Flutter (Dart) — one codebase for **Android + iOS** | Both platforms from one codebase; `just_audio` gives exact clip seeking on both |
| Authentication | Firebase Authentication (Google + email in v1; phone later) + anonymous guest | Battle-tested, free to 50k MAU; don't build auth yourself; anonymous→linked backs guest mode |
| Database | Cloudflare D1 (serverless SQLite) | Relational SQL fits the catalog + leaderboards; free, same vendor as audio |
| Compute / API (the backend) | Cloudflare Workers — written in **TypeScript** (or JS) | Serverless API next to the data; verifies Firebase tokens |
| Audio storage/CDN | Cloudflare R2 | **Free egress** — the decisive factor for an audio app; 10 GB storage free |
| Admin dashboard (a separate frontend UI, **not** the backend) | React / Next.js — or any web framework; also TypeScript | Internal web page for admins to manage the catalog; talks to the Workers API |
| Ingestion | Python scraper + ffmpeg clip cutter (already built) run as jobs | Reuses existing tooling |
| Ads | Google AdMob (`google_mobile_ads` plugin, with mediation) | Default; fills domestic + diaspora |

_Note: the **backend/API** is Cloudflare Workers; **React/Next.js appears only as the admin dashboard**, a separate internal web UI — it does not serve the game. These are not language-vs-language choices: both the Workers backend and a React admin page are written in **TypeScript**, so TypeScript isn't an alternative to React — it's what both are built in._

**Why this stack (Flutter + Firebase Auth + Cloudflare)?** Data, audio, and API all sit on Cloudflare — one vendor, all free at launch scale — authentication is delegated to Firebase so nobody builds it, and the client is Flutter so Android and iOS ship from one codebase.

- **Flutter over native, because iOS is in scope.** Maintaining separate Kotlin (Android) and Swift (iOS) apps is roughly double the work forever; Flutter compiles one Dart codebase to both. The earlier worry — precise audio control — is handled by `just_audio`, whose `ClippingAudioSource` plays an exact start→end range (covering both "intro" and "middle" modes) on top of the native engines (ExoPlayer / AVFoundation). Prototype the clip-seek early to confirm it feels tight.
- **Data lives in D1 (SQLite), which is relational SQL.** The catalog is a web of joins — artists ↔ aliases, tracks ↔ generations, packs ↔ pack_tracks, users ↔ scores ↔ leaderboards — modeled natively with foreign keys and real queries ("top players per generation this week"). _(This is why Firebase's document/NoSQL Firestore was rejected for the data layer; the relational fit is a wash between D1 and Postgres/Supabase, and D1 wins only by keeping data on the same vendor as the audio.)_
- **Audio stays on R2** for free egress — the decisive cost factor for an audio app, and the reason Firebase Cloud Storage (which began requiring a billing account in February 2026) isn't used for files.
- **Auth is Firebase, used standalone.** Firebase handles login and issues a signed token (JWT); a Cloudflare Worker verifies it against Google's public keys, then reads/writes D1 keyed by the Firebase user ID. Firebase never touches game data — it only answers "is this really this user?" Free to 50k monthly active users, minimal lock-in. **Anonymous auth** backs the guest mode (FR-13): a guest gets a throwaway identity that is *linked* to their Google/email account on registration, so guest scores carry over.

**Auth method rollout:** launch with **Google + email sign-in** (free, no billing account, reliable). Add **phone/SMS login later** only if users want it — phone auth needs Firebase's paid Blaze plan and costs ~$0.01–$0.06 per SMS verification, and SMS deliverability on Ethiopian carriers can be unreliable. _(Google's SIM-based verification, launched May 2026, is a no-SMS alternative worth evaluating if phone login becomes a priority.)_

**Alternative considered:** Supabase (Postgres + built-in Auth + auto-API) would collapse auth, DB, and API into one platform and is a fine choice — especially if the team already knows it. Traded away here to keep data/audio/API on one vendor (Cloudflare) with Firebase handling only identity. _(assumption: recommendation, not locked — existing team expertise can tip the call.)_

**Flutter client libraries:** `just_audio` (precise clip playback, offline files) · `drift` or `sqflite` (local score/metadata cache) · `path_provider` + a background-download plugin (pack download & storage) · `firebase_auth` via FlutterFire (login) · `google_mobile_ads` (ads) · bundled **Noto Sans Ethiopic** (guaranteed Fidel rendering on every device).

**Data model (core tables):**
`artists`, `tracks`, `clips` (start_time, length, type: intro|middle), `generations`, `packs`, `pack_tracks`, `users`, `scores`, `leaderboard_entries`, `game_sessions`, `royalty_usage_log`, `ad_events`, `admin_users`.

**API (representative endpoints):**

| Endpoint | Method | Purpose |
|---|---|---|
| `/auth/*` | — | Login via Firebase Auth SDK (client-side); Workers verify the Firebase JWT per request |
| `/packs` | GET | List available packs + versions |
| `/packs/{id}/manifest` | GET | Pack manifest (tracks, clip URLs, checksums) |
| `/rounds/next` | GET | Serve a round (clip ref + 4 choices) for a mode/era |
| `/plays` | POST | Log a clip play (feeds royalty log + analytics) |
| `/scores` | POST | Submit round events; server computes & validates score |
| `/leaderboard` | GET | Global/weekly, filterable by generation |
| `/admin/*` | — | Scraper control, catalog CRUD, review queue, pack publish, royalty export (admin-authed) |

**Generations / eras (starting taxonomy, admin-editable):**
Golden Age (pre-1980s) · 80's · 90's · 2000s · Modern (2010s+). Genre tags layer on top (tizita, ethio-jazz, traditional, pop, hip-hop).

**Offline & sync:** packs are immutable + versioned; the app downloads a pack, verifies checksums, and plays entirely offline. Scores captured offline queue locally and sync on reconnect; server is the source of truth for leaderboards and resolves conflicts by timestamp.

**Error handling & edge cases:** missing/short audio (skip track, flag to admin); corrupted pack download (re-fetch via checksum mismatch); duplicate score submissions (idempotency key); clock skew on offline scores (server timestamp wins); no network at launch (play cached packs); guest→account link failure (retain local scores, retry link).

**Performance & scale:** clip ≈ 150 KB (10s); 1,000-song catalog ≈ 150 MB total. R2 free tier (10 GB storage, free egress, 10M Class-B ops/mo) and D1 free tier (5 GB storage, 5M row-reads/day) cover well beyond early scale at $0. Round-serving and leaderboard reads should be < 300 ms p95.

**D1 write-limit watch-out:** D1's free tier allows 100,000 row-writes/day. Logging every clip play (FR-10) as its own row would exceed this at modest scale (e.g. 5,000 users × 30 rounds = 150,000/day). Mitigate by **batching/aggregating play logs** (one summarized row per user-session, or hourly roll-ups) or routing raw play events to Cloudflare's analytics instead of individual D1 rows — the royalty report only needs per-track play *counts*, not a row per play.

**Security & compliance:** every Worker request verifies the caller's Firebase JWT (against Google's public keys) and authorizes by the Firebase user ID, so users only read/write their own data; server-side score validation to resist leaderboard cheating (see R-5); admin dashboard behind separate admin auth + role check; Google Play & Apple App Store content-rating compliance; privacy policy covering AdMob data, account data, and Firebase Auth as the identity processor.

**Dependencies (third parties / teams):**
- **Music association license** — must cover **sound recordings (masters)**, not only compositions, for the catalog to be usable. _(blocking; see R-1.)_
- Cloudflare (D1, Workers, R2), Firebase Authentication, Google AdMob.
- **Google Play Developer account** — $25 one-time.
- **Apple Developer Program** — $99/year (recurring), plus a **Mac running Xcode** to build and release iOS. Apple's App Store review is stricter and may request proof of music licensing.
- Existing in-house tooling: ethiozeima scraper + clip cutter.

**Rollout strategy:**
1. Internal catalog build (scraper → admin review → packs) — no public app yet.
2. Closed beta via Telegram/Facebook Ethiopian-music groups (validates the fun + spread).
3. Open beta on Google Play + Apple TestFlight (Amharic + English).
4. GA on both stores + begin sponsorship/ad optimization, diaspora-targeted.

## 6. Timeline / Milestones

_(No fixed deadline — "ASAP." Dates below are aspirational sequencing, not commitments.)_

| Phase | Deliverable |
|---|---|
| M0 | License confirmed (masters); catalog schema finalized |
| M1 | **UI/UX design (before any app development):** user flows, wireframes, then high-fidelity mockups of all key screens in **both Amharic and English**, and a clickable prototype — reviewed and signed off before coding starts. _(Can run in parallel with M2 ingestion.)_ |
| M2 | Ingestion pipeline live; ~200 curated, verified tracks + packs |
| M3 | Backend + auth + leaderboards; admin dashboard v1 |
| M4 | Flutter app built to the approved M1 design: both game modes, generations, offline packs, bilingual, guest mode, ads — on Android + iOS |
| M5 | Closed beta (Play + TestFlight) → fixes |
| M6 | Open beta on both stores |
| M7 | GA |

**Key screens to design in M1:** home/landing · game-mode select (intro / middle) · era & genre select · the round screen (clip playing, timer, answer options) · correct/wrong feedback · round results & score · leaderboard · pack browse & download · sign-in / register prompt · settings with the Amharic↔English toggle. Design both languages from the start — Amharic text runs longer and uses the Fidel script, so layouts must be checked in both so nothing clips or overflows.

## 7. Open Questions & Risks

| # | Risk / question | Owner | Mitigation |
|---|---|---|---|
| R-1 | Does the association license actually cover **masters**, in writing? | You + lawyer | **Confirmed as the plan:** secure written master coverage before public launch. This is what makes the scraped audio (R-3) usable. |
| R-2 | Transliteration/dedup messiness in the catalog | Catalog admin | Pipeline auto-transliterates (Amharic↔Latin) on ingestion and flags uncertain or duplicate entries into an **admin review queue** (FR-20); admin verifies/corrects the flagged list before tracks go live. |
| R-3 | Fan-rip audio quality (scraped MP3s) | Catalog admin | **Decision:** use the scraped audio as-is for v1 — quality is acceptable for the game. Revisit only if players complain. (Relies on R-1 master coverage.) |
| R-4 | Catalog cold-start (too few songs = repetitive) | Catalog admin | Launch with a curated ~200+ across eras before open beta. |
| R-5 | Leaderboard cheating | Eng | Server-side score validation + anomaly detection (see briefing notes below). |

**Low-priority / accepted (tracked, not blocking):**
- _User data cost affecting retention_ — not a major concern; already mitigated by the offline-pack + small-clip design.
- _Low domestic ad eCPM_ — accepted; revenue is expected to skew diaspora. Not treated as a project risk.

### R-5 notes — leaderboard cheating defenses
The core principle: **never trust the client.** A determined user can inspect or modify the app, so any score the phone sends can be forged. Defenses, lightest to strongest:
- **Server-authoritative scoring.** Don't let the app send a final score; have it send the *answers/events* (which track, which option, response time) and let the Worker compute the score from the known correct answers. The client never decides points.
- **Sanity bounds.** Reject or flag impossible results — scores above the max achievable for the rounds played, response times faster than human reaction (e.g. < 200 ms), more rounds than were served.
- **Rate / pattern checks.** Flag accounts whose submissions arrive too fast, too regularly, or far outside normal distributions (anomaly detection on score velocity and accuracy).
- **Auth required to rank.** Only registered accounts appear on the leaderboard (FR-14), so cheaters can't spam anonymous entries and are easier to ban.
- **Separate weekly boards + shadow-banning.** Weekly resets limit the damage of any single exploit; suspected cheaters can be shadow-banned (they see their score, others don't) rather than tipped off.

For v1, server-authoritative scoring + sanity bounds covers the vast majority; the rest can be added if abuse appears.

## 8. Appendix

- Built tooling: `ethiozeima_scraper.py` (metadata + audio ingestion with royalty usage logging), `clip_maker.py` (ffmpeg clip cutting, per-track start times).
- Infra cost note: the whole stack (Cloudflare D1/Workers/R2 + Firebase Auth) is on free tiers at launch scale, so hosting is effectively $0. The real recurring costs are association royalties, the Apple Developer Program ($99/yr), and — only if phone login is added — per-SMS auth fees. The $25 Play Store fee is one-time.
