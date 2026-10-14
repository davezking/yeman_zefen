# Scoring

The single source of truth for how a round and a session score. The app shows a provisional score while the player
plays. The server (`POST /v1/sessions`, Phase 3) recomputes the score from the round events and decides the real one.

The app implements this in `app/lib/features/game/domain/scorer.dart`. The worked examples below are a table that a
test reads (`app/test/features/game/domain/scorer_test.dart`) and runs through the code, so this document and the app
cannot drift apart. The server must pass the same table.

## The rules

Copied verbatim from `docs/architecture.md` §4, "Scoring formula":

- Base points by clip length: 10 s = 100, 5 s = 150, 3 s = 200. "Middle" mode multiplies by 1.25.
- Answer window = clip length + 5 s. Speed bonus = round(0.5 × base × max(0, 1 − response_ms / window_ms)).
- Correct = base + bonus. Wrong = 0. A rewarded-ad hint (removes 2 options) halves the round's points.
- Generation-guess mode (FR-12): correct = 120 + speed bonus on the 10 s window, no difficulty tiers.
- **Sanity bounds:** response_ms < 200 marks that round invalid (0 points) and flags the session. More than 50 rounds per session is rejected. The sum of response times must fit inside the session's duration. Options must be 4 distinct, existing IDs that include the correct one.

## How the rules are applied

The rules above leave some cases open. These are the choices the app makes. The server must make the same ones. Items
marked **open** are not settled by the architecture doc and need a decision before the Phase 3 server is written.

| Case | Choice |
|---|---|
| Difficulty and clip length | easy = 10 s, medium = 5 s, hard = 3 s (FR-7). The clip length is the part of the clip that plays, so it sets the base points and the window. |
| `round` | Round half up. Every value here is non-negative. |
| Exact arithmetic | All formulas are computed on integers, below, so the app and the server cannot differ through floating point. They give the same result as exact arithmetic with round half up. |
| Middle multiplier | Applied to the base before the bonus, then rounded: 100 → 125, 150 → 187.5 → **188**, 200 → 250. The bonus uses the rounded base. |
| `response_ms` | From the moment audio actually starts playing to the moment the player taps an option. In the app it starts when `ClipPlayer.play()` returns, not when the screen is built. |
| Answer after the window (**open**) | The formula clamps the bonus to 0, so a correct answer after the window would still earn the base. The app never allows it: when the window runs out the round ends as a timeout, recorded with `chosenId: null`, which scores 0. The server should treat `chosenId: null` as wrong, and decide whether a late non-null answer should score by the formula or be flagged. |
| Hint | Halves the total (base + bonus), rounded half up. The payload's `optionIds` still holds all 4 options; `hintUsed: true` says 2 were removed on screen. |
| Invalid round | `response_ms < 200` scores 0 and flags the session, whether the answer was right or wrong. The round still counts as played. 200 ms exactly is valid. |
| Generation-guess mode (**open**) | Base 120. "On the 10 s window" is read as the general rule applied to a 10 s clip: window = 10 s + 5 s = 15 s. If it meant a 10 s window, the bonus changes. Difficulty is ignored. |
| Wrong answer | 0 points, no bonus, valid. |

## Integer form

```
base      = easy 100 | medium 150 | hard 200 | generation 120
base      = (base * 5 + 2) / 4                       # middle mode only, integer division
window    = clip_ms + 5000                           # clip_ms = 10000 / 5000 / 3000; generation uses 10000
bonus     = response_ms >= window ? 0
          : (base * (window - response_ms) + window) / (2 * window)     # integer division
points    = base + bonus
points    = (points + 1) / 2                         # only when a hint was used, integer division
```

`/` is integer division (floor) on non-negative integers. The bonus form is `floor(x + 1/2)` for
`x = base × (window − r) / (2 × window)`, which is `round(0.5 × base × (1 − r / window))` with half rounding up.

## Worked examples

Each row is checked by a test. `Difficulty` is ignored in generation mode. `Valid` is `no` when the response was under
200 ms.

| ID | Mode | Difficulty | Correct | Response (ms) | Hint | Base | Window (ms) | Bonus | Points | Valid |
|---|---|---|---|---|---|---|---|---|---|---|
| E1 | intro | easy | yes | 2000 | no | 100 | 15000 | 43 | 143 | yes |
| E2 | intro | medium | yes | 1500 | no | 150 | 10000 | 64 | 214 | yes |
| E3 | intro | hard | yes | 1000 | no | 200 | 8000 | 88 | 288 | yes |
| E4 | intro | easy | no | 2000 | no | 100 | 15000 | 0 | 0 | yes |
| E5 | middle | easy | yes | 2000 | no | 125 | 15000 | 54 | 179 | yes |
| E6 | middle | medium | yes | 1500 | no | 188 | 10000 | 80 | 268 | yes |
| E7 | middle | hard | yes | 1000 | no | 250 | 8000 | 109 | 359 | yes |
| E8 | intro | easy | yes | 2000 | yes | 100 | 15000 | 43 | 72 | yes |
| E9 | intro | medium | yes | 1500 | yes | 150 | 10000 | 64 | 107 | yes |
| E10 | intro | easy | yes | 15000 | no | 100 | 15000 | 0 | 100 | yes |
| E11 | intro | easy | yes | 20000 | no | 100 | 15000 | 0 | 100 | yes |
| E12 | intro | easy | yes | 199 | no | 100 | 15000 | 0 | 0 | no |
| E13 | intro | easy | yes | 200 | no | 100 | 15000 | 49 | 149 | yes |
| E14 | intro | easy | no | 150 | no | 100 | 15000 | 0 | 0 | no |
| E15 | generation | - | yes | 3000 | no | 120 | 15000 | 48 | 168 | yes |
| E16 | intro | hard | yes | 7000 | no | 200 | 8000 | 13 | 213 | yes |
| E17 | middle | hard | yes | 1000 | yes | 250 | 8000 | 109 | 180 | yes |

What the rows show:

- **E1–E3:** the base and window by difficulty. E3 is an exact tie: `0.5 × 200 × (1 − 1000/8000) = 87.5`, which rounds
  up to 88. E16 is another: `12.5` rounds up to 13.
- **E4:** a wrong answer is 0.
- **E5–E7:** the middle multiplier. E6 is the 187.5 case: the base is 188.
- **E8, E9, E17:** the hint halves the total. E8 is 143 → 71.5 → 72. E17 is 359 → 179.5 → 180.
- **E10, E11:** the bonus is 0 at the window and stays 0 after it. The base is still earned (see the open item above).
- **E12–E14:** under 200 ms is invalid and scores 0, right or wrong. 199 is invalid and 200 is valid.
- **E15:** generation-guess mode.

### A session

A session's score is the sum of its rounds' points. Rounds E1, E4 and E8 played in an intro/easy session give
143 + 0 + 72 = **215**. If a fourth round were E12, the total stays 215 and the session is flagged.

## Checks the app does and does not do

| Check | App | Server |
|---|---|---|
| `response_ms < 200` is invalid, 0 points, flags the session | yes | yes |
| More than 50 rounds is rejected | the generator never makes more | yes |
| The sum of response times fits the session's duration | no | yes |
| Options are 4 distinct, existing ids that include the correct one | the generator guarantees it | yes |
