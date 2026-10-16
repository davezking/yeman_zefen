# Session payload

What the app sends to `POST /v1/sessions` for one finished session, and what it stores in `pending_sessions` until it
can. The app sends round **events**, never a score: the server computes the score from them (`docs/scoring.md`).

The app builds it in `app/lib/features/game/domain/session_payload.dart` (`SessionRecorder`). A test compares the keys
of the example below with what the recorder produces.

## Shape

Copied from `docs/architecture.md` §5, "Session payload (shape)":

```json
{ "id": "uuid", "mode": "intro|middle|generation", "generationId": 0, "difficulty": "easy|medium|hard",
  "clientStartedAt": 0, "clientEndedAt": 0, "offline": true,
  "rounds": [{ "trackId": 0, "question": "song|artist|era", "optionIds": [0,0,0,0],
               "chosenId": 0, "responseMs": 0, "hintUsed": false }],
  "ads": { "interstitialShown": 0, "rewardedCompleted": 0 } }
```

## Example

A real session has 10 rounds. Two are shown.

```json
{
  "id": "6f0d2c1e-4b7a-4c52-9d0e-1a2b3c4d5e6f",
  "mode": "intro",
  "generationId": 0,
  "difficulty": "medium",
  "clientStartedAt": 1760000000000,
  "clientEndedAt": 1760000095000,
  "offline": true,
  "rounds": [
    {
      "trackId": 41,
      "question": "song",
      "optionIds": [12, 41, 7, 90],
      "chosenId": 41,
      "responseMs": 2310,
      "hintUsed": false
    },
    {
      "trackId": 55,
      "question": "artist",
      "optionIds": [3, 8, 21, 14],
      "chosenId": null,
      "responseMs": 10000,
      "hintUsed": false
    }
  ],
  "ads": { "interstitialShown": 0, "rewardedCompleted": 0 }
}
```

## Fields

| Field | Meaning |
|---|---|
| `id` | A UUID made once per session. It is the server's idempotency key, so a retried upload is not counted twice. |
| `mode` | `intro` or `middle` (which clip played), or `generation` for the era-guess mode. |
| `generationId` | The era the session was limited to, or `0` for all eras. |
| `difficulty` | `easy` = 10 s clip, `medium` = 5 s, `hard` = 3 s. |
| `clientStartedAt`, `clientEndedAt` | Epoch milliseconds, UTC, from the device clock. |
| `offline` | True when the device had no connection during the session. |
| `rounds[].trackId` | The track whose clip played. The server knows its artist and era. |
| `rounds[].question` | `song`: the options are track ids. `artist`: the options are artist ids. `era`: the options are era ids. |
| `rounds[].optionIds` | Exactly 4 distinct ids, in the order shown, including the correct one. |
| `rounds[].chosenId` | The option the player tapped. **`null` when the answer window ran out**, see below. |
| `rounds[].responseMs` | Milliseconds from audio actually starting to the tap. For a timeout, the length of the window. A round paused by a call or by the app going to the background plays its clip again on resume, and the time used before the pause is included, so pausing does not reset the clock. |
| `rounds[].hintUsed` | True when a rewarded-ad hint removed 2 options on screen. `optionIds` still lists all 4. |
| `ads` | Counts of ads shown in the session. Both are 0 until ads are added. |

The payload has no score and does not say which option was correct. The server works both out from `trackId` and
`question`.

## `chosenId` is null for a timeout

The shape in the architecture doc gives `chosenId` as a number. A round with no answer still plays its clip, so the app
records `chosenId: null` and `responseMs` equal to the window. The server accepts `null`, scores it 0, and counts the
round as played.

## What the server answers

`POST /v1/sessions` returns `200 { "score": 286, "rounds": [{ "points": 143, "correct": true }, …], "flagged": false }`,
one entry per round in order. Sending the same `id` again returns the stored result unchanged and adds nothing, even if
the payload differs. An `id` another player already used is `409 session_conflict`. A malformed payload is
`400 validation_error`, and one that cannot come from a real game is `422 invalid_session` (`docs/scoring.md`, "What the
server adds"). Unknown fields are ignored, so an older server accepts a newer app's payload.

## How the app uploads

`app/lib/features/game/data/session_sync.dart` sends the sessions in `pending_sessions`, oldest first among those that
are due, one at a time:
when the app starts, once the player has a uid (a session played before the first sign-in waits for it), when the
connection comes back, after each session ends, and when the app returns to the foreground.

| Answer | What the app does |
|---|---|
| `200` | Deletes the row and keeps the server's `score` in `recent_sessions.server_score`, which is the number a results list should show. |
| Offline, `5xx`, `429`, `401`, `403`, `404`, `408`, or a status that is not 2xx or 4xx | Keeps the row and waits 30 s, doubling each failed attempt up to 1 hour (a `429`'s `Retry-After` if longer). Starting the app, signing in and the connection coming back skip the wait only for a session that failed for want of a connection; a wait after a server answer holds. The rest of the queue waits for the next pass. |
| Any other `4xx` (`400`, `409`, `413`, `422`) | Parks the row for good (`parked`), with the reason in `last_error`. The rest of the queue carries on. |

A row is deleted only after a `200`, and the server answers a repeated `id` with the stored result, so an app killed
mid-upload loses nothing and counts nothing twice.

## Rules the app keeps

- A session has 1 to 50 rounds. The app plays 10.
- `chosenId` is `null` or one of `optionIds`; the recorder refuses anything else.
- `responseMs` is not negative.
- Rounds are in the order they were played.
