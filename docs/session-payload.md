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
| `rounds[].responseMs` | Milliseconds from audio actually starting to the tap. For a timeout, the length of the window. |
| `rounds[].hintUsed` | True when a rewarded-ad hint removed 2 options on screen. `optionIds` still lists all 4. |
| `ads` | Counts of ads shown in the session. Both are 0 until ads are added. |

The payload has no score and does not say which option was correct. The server works both out from `trackId` and
`question`.

## Open: `chosenId` is null for a timeout

The shape in the architecture doc gives `chosenId` as a number. It does not say what a round with no answer looks like,
and the app has to record one, because the clip plays and the window runs out. The app records `chosenId: null` and
`responseMs` equal to the window. The server should accept `null`, score it 0, and treat it as a round that was played.
If the server would rather not accept `null`, the alternative is a sentinel such as `0` (no id is 0); this needs a
decision before the Phase 3 endpoint is written.

## Rules the app keeps

- A session has 1 to 50 rounds. The app plays 10.
- `chosenId` is `null` or one of `optionIds`; the recorder refuses anything else.
- `responseMs` is not negative.
- Rounds are in the order they were played.
