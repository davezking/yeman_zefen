# Device check: a full round flow

Status: **code done, device run not yet done.** Fill in the results from a real Android phone and a real iPhone.
Task: P1S4 task 5 (`docs/phase-1-sprint-4-prompts.md`). The tables are empty on purpose.

## What exists

Home → Song packs (install) → Play (mode, era, difficulty, questions) → 10 rounds → Results. A finished session is
saved on the device in `pending_sessions` as the payload in `docs/session-payload.md`. The best score is kept per mode
and era, and rounds whose clip is missing or will not play are skipped and counted.

In the **dev** flavor the home screen also has "Clip playback debug" and "Saved sessions debug". The second one lists
the saved payloads, their fastest and slowest response time, whether the device was offline, and the clip error count.

## Setup

1. Run a dev build on the device (`app/README.md`, "Running on a phone"). For a real phone, `config/dev.local.json`
   needs the LAN address of the API, and the API needs real published packs (`wrangler dev --ip 0.0.0.0`).
2. Open Song packs and install at least one pack with 4 or more songs (a full 10-round session needs 10).

## Checks

Run each on **both** devices and write down what happened.

1. **Install.** Install a pack. Watch the progress. Airplane mode part-way, then back on: does it finish?
   *(This is also the task 2 check.)*
2. **Offline session.** Turn on airplane mode, close and reopen the app, then play a full 10-round session. Every
   round should play and the results screen should show.
3. **Saved payload.** Home → Saved sessions debug. Open the session. Compare it with `docs/session-payload.md`: the same
   keys, `offline: true`, 10 rounds, `chosenId` one of `optionIds`.
4. **Response times.** On the same screen, read the fastest and slowest response. Open a few rounds. None should be 0 ms
   or under 200 ms, and they should look like a person's (a second or two, not all identical).
5. **Timeout.** Let one round run out. It should show "Time's up", and the payload should have `chosenId: null`.
6. **Skipped clip.** (Optional.) Delete one clip file with a file browser or `adb`, then play. That round should be
   skipped, the results should say so, and "Clip errors" should go up by one.
7. **Interruption.** Phone call or alarm during a round: the round should pause with a Resume button. Resuming plays
   the clip again, and the countdown bar carries on from where it stopped rather than starting full. Then press Home
   during the right/wrong pause between rounds and wait a few seconds: no clip should play while the app is away, and
   coming back should show Resume for the next round.
8. **Best score.** Play twice in the same mode and era. The second results screen should say "New best score!" or show
   the earlier best.

## Results

Devices: _Android: model, OS version._ _iOS: model, OS version._ Build: _flavor, debug/profile/release._

| Check | Android | iPhone | Notes |
|---|---|---|---|
| 1. Install, with airplane mode part-way | | | |
| 2. Full 10-round session offline | | | |
| 3. Saved payload matches the doc | | | |
| 4. Response times look human (fastest / slowest, ms) | | | |
| 5. Timeout recorded with no answer | | | |
| 6. Skipped clip counted | | | |
| 7. Interruption pauses and resumes | | | |
| 8. Best score kept | | | |

## Conclusions

_To fill in: whether the playable loop works offline on both platforms, and anything that needs a follow-up task._
