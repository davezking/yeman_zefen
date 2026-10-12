# Phase 4 · Sprint 2 — Game experience

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: the core loop at production quality, with all modes and difficulties, the era-guess bonus mode, polished feedback, and graceful handling of every failure the PRD lists.

---

## Task: Round screen wired to the real engine and audio

**Model:** sonnet — the most important screen; real audio timing has to match the designed motion and pacing.

**Context:** `ClipPlayer` (preloading, start latency already measured in `docs/spikes/clip-playback.md`), `RoundGenerator`, `Scorer`, and `SessionRecorder` exist. The approved round screen, with all its states, is in `app/lib/prototype/screens/` (plain data plus callbacks; it currently runs on a fake timer). Follow the phase convention from Sprint 1: move it to `features/game/ui/` and wire it, don't restyle. Rules: the answer window is clip length + 5 s, and the response timer starts when audio actually starts.

**Do this:**
1. Move the round screen and drive each of its states from the real engine:
   - Round counter and running score.
   - An audio-playing indicator, animated from the player's actual playing state.
   - A countdown bar for the answer window.
   - Four option tiles using the shared component.
   - A "replay" button only if the approved screen includes it. If it does, record replays in the round event as `replays` and agree with yourself whether replays affect points; update `docs/scoring.md` and both scorers' fixtures if so.
2. Answer flow: stop audio immediately, lock input, animate correct and wrong states (and reveal the correct option), show points earned, then advance after the designed delay. The next clip is already preloaded.
3. Handle app backgrounding mid-round: pause audio and timer, and show a resume overlay on return. A backgrounded round doesn't count toward response time.
4. Optional haptics and sound effects, gated by settings.

**Before moving on, check:**
- On a mid-range Android phone, no visible jank (run a profile build and check the frame chart).
- Backgrounding and returning doesn't corrupt `responseMs`.
- The time from tap to the next clip starting matches the pacing approved in the prototype.

---

## Task: Modes, difficulties, and the generation-guess bonus mode

**Model:** sonnet — extends engine and server scoring consistently on both sides.

**Context:** FR-5/6/7 (intro and middle modes, 3/5/10 s difficulty) are already supported by the engine. FR-12 adds a bonus mode where the player guesses which **era** a song belongs to. The scoring for it is defined in `docs/scoring.md` (generation mode: 120 + speed bonus over a 10 s window). Server scoring is in `api/src/lib/scoring.ts` and validation in `api/src/routes/v1/sessions.ts`. Shared fixtures are in `docs/fixtures/scoring.json`.

**Do this:**
1. Engine: a `question: 'era'` kind. Options are 4 distinct generation IDs including the correct one; if there are fewer than 4 eras in total, use all of them. The clip is always the intro at 10 s.
2. Server validation for `era` questions: options must be valid generation IDs, and correctness compares against `tracks.generation_id`. Add fixtures and tests to both sides.
3. Wire up mode select so all combinations work: intro or middle × easy, medium, or hard × song, artist, or mixed questions, plus the era mode.
4. Leaderboards: era-mode sessions count toward the all-eras board under `generation 0`. Document this in `docs/scoring.md`.

**Before moving on, check:**
- Every mode and difficulty combination plays a full session and syncs with matching client and server scores.
- The shared fixtures pass on both sides.

---

## Task: Wire the results screen

**Model:** haiku — an existing screen connected to data that already exists.

**Context:** The session result (local provisional score, then the authoritative server score after sync), per-round results, local bests, and the register prompt controller exist. The approved results screen (provisional, synced, new-best, and register-prompt variants) is in `app/lib/prototype/screens/`.

**Do this:**
1. Move the prototype results screen (all variants) to `features/game/ui/` and wire it: total score, accuracy, best streak, and a per-round list (track name in the current locale, correct or wrong, points). Show "syncing…" until the server score arrives, then update it, noting any difference.
2. "New best" celebration when beating the local best for that mode and era.
3. Actions: play again (same settings), change mode, and leaderboard.
4. Show the register prompt here when the controller says so.

**Before moving on, check:**
- The score updates in place from provisional to server-confirmed after sync.
- The screen matches its approved screenshots in both languages.

---

## Task: Edge-case handling — bad audio, corrupt packs, no network

**Model:** sonnet — several failure paths that must degrade gracefully and report back.

**Context:** The PRD lists these cases: missing or short audio (skip the track and flag it to admin), a corrupted pack download (re-fetch on checksum mismatch), duplicate score submissions (already idempotent), clock skew (server time wins, already handled), no network at launch (play cached packs), and guest-to-account link failure (keep local scores and retry the link).

**Do this:**
1. Audio failure during a round (file missing, decode error, or under 1 s of audio): skip the round without penalty, mark the track `broken` locally so it's excluded until the pack is re-verified, and report it via a new `POST /v1/reports/clip { trackId, clipType, error }` that creates a deduplicated `review_items` row (`missing_audio`). Add a rate limit of 10 reports per user per day.
2. On app start, re-verify installed packs' checksums in the background, once per pack version, then weekly. On a mismatch, re-download just the bad files.
3. No network at launch: the app goes straight to home with installed packs. The leaderboard and packs screens show an offline state with retry.
4. Link failures: show a friendly error, keep guest data intact, and offer a retry. Never leave the app signed out.
5. Zero installed packs and offline: show a clear empty state explaining that a first download is needed.

**Before moving on, check:**
- Manually deleting a clip file mid-session skips that round and later shows up in the admin review queue.
- Corrupting one byte of a clip file gets it repaired on the next launch.
- Airplane-mode cold start reaches a playable home screen.
