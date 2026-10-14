# Design handoff (Phase 2 · Sprint 1)

The approved design for Yeman Zefen, in direction **F · Adey**: sunny yellow, cream cards with a press edge, and a cassette as the playing indicator. Sprint 2 builds the Flutter theme and screens from this folder.

| File | What it is |
|---|---|
| `tokens.json` | Colors (semantic, correct/wrong, timer, era accents), typography with separate Fidel and Latin line heights, spacing, radii, elevation, sizes, motion, and game timings. Light theme only. |
| `screens.md` | Every screen and state: layout, components, content keys, and behavior. Start here. |
| `copy.md` | Every string in English and Amharic, keyed for the ARB files. **The Amharic is a first draft awaiting native-speaker review.** |
| `artifacts/` | The HTML source of each approved board (`H01`–`H21`) and the interactive round prototype (`P00`). Read exact sizes, colors and spacing from these. |
| `screens/` | A screenshot of each board, English and Amharic side by side (WebP, 2×). |

## Reading the HTML

The `.dc.html` files come from the Design canvas (claude.ai artifact "Yeman Zefen Design Brief"). Each is a template plus a small logic class:

- Markup and inline styles are inside `<x-dc>`; shared classes are in the `<style>` block under `<helmet>`.
- `{{L.name}}` holes are filled from the `langs` array in the `<script type="text/x-dc">` class at the bottom of the file, which holds the English and Amharic strings for that board.
- `<sc-for>` repeats, `<sc-if>` shows conditionally.
- `<dc-import name="X" variant="y">` renders board `X` in state `y`. For example, `H07-Correct` is `H06-Round` with `variant="correct"`.

The canvas runtime (`support.js`) is not included, so the files don't render when opened directly. Use the screenshots to see them, or open the canvas.

## What changed after the Step 1–3 boards

The Step 1 copy deck, the Step 2 wireframes and the Step 3 directions are still on the canvas as history. Where they disagree with this folder, this folder wins. The main changes:

- **Bottom bar:** Home · Play · Settings. The leaderboard opens from Home.
- **Play-first delivery:** the design matches `docs/architecture.md`. That means built-in starter songs, streamed clips with prefetch, and offline packs in Settings › Offline play with a mobile-data toggle and Clear cache.
- **Next song:** when a clip isn't ready, the round shows a 10 s loading state and then skips the round. There is no error screen.
- **Ads and timing:** interstitials are mandatory, every 3 rounds. The rewarded hint is opt-in, and its sheet closes after 8 s. The timer pauses while the sheet is open and while the ad plays.
- **Feedback:** a correct answer shows for 1 s. A wrong answer shows for 5 s, and a tap skips it.

## Open items

- **Amharic review** by a native speaker (sprint exit criterion).
- **No dark theme** was designed. The theme extension should still take one later.
- **Interstitial frequency:** `/v1/config` defaults to 3 rounds, and the architecture and later sprint prompts are updated to match.
- **Paused time:** the scoring doc now says that `response_ms` excludes the paused time. The app's scorer must measure it that way when the hint is built.
