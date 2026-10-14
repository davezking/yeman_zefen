# Phase 2 · Sprint 1 — Design in Claude artifacts (not Claude Code)

This sprint happens **in a claude.ai chat, using artifacts**, not in Claude Code. You see each screen rendered right away and iterate by asking for changes. There are no PRs this sprint. The output is a **handoff package** committed to `docs/design/`, which the Claude Code tasks in Sprint 2 build from.

Work through the steps in order, in one chat or a Project, so the context carries from step to step.

---

## Step 1 — Brief, screen list, and copy

Ask Claude to draft, from the PRD (attach it):
- **A short design brief:** the two personas, tone (warm and nostalgic, never childish), principles (one-thumb play, Fidel-first typography, nothing blocks the first round: no sign-up and no download prompt, see "Play-first delivery" in `docs/architecture.md` §3), and accessibility targets (WCAG AA contrast, 48 dp touch targets, text scale up to 1.3).
- **The full screen list, with states for each:**
  - The PRD's key screens: home, mode select, era & genre select, round, correct/wrong feedback, results, leaderboard, sign-in / register prompt, and settings with the language toggle. Pack browse & download lives **inside settings** as "Offline play", not on home or in onboarding.
  - Screens the PRD implies but doesn't list: first launch (straight into play from the bundled starter clips), ad-consent placement, forced update, offline, out of songs (offline and every clip on the device recently played, pointing to Settings → Offline play), next song loading (rare: a slow connection in an era with no songs on the device yet), errors, and loading.
- **A copy deck:** every string in English and Amharic.

You review the Amharic yourself or with a native speaker you trust.

## Step 2 — Wireframes

Ask for grayscale wireframes of every screen as phone frames (360×780), **English and Amharic side by side** with the real strings, so long Amharic text is checked from the start. Ask for two round-screen layout options (e.g. a 2×2 grid vs a vertical list of answers), and pick one.

## Step 3 — Visual direction

Ask for **three distinct style directions**. Each should show the palette, the font pairing with Noto Sans Ethiopic using real Amharic and English text, answer buttons in idle/correct/wrong states, and era chips for all five eras. Pick one, or mix elements from several. Check that correct and wrong differ by an icon as well as color, and look at the result on your phone.

## Step 4 — Hi-fi screens

Ask for every screen and state from Step 1 in the chosen style, in both languages. Have Claude build the round screen as an interactive artifact with a fake timer and answer feedback, so you can judge the pacing. Iterate until you're happy.

## Step 5 — Handoff package (required before Sprint 2)

Ask Claude to produce these files, then commit them to `docs/design/`:
- `tokens.json` with:
  - semantic colors (background, surface, primary, correct, wrong, timer, era accents; light and dark if designed)
  - typography (families, size scale, weights, separate line heights for Fidel and Latin)
  - spacing, radii, elevation, and motion (durations and curves)
- `screens.md`: for every screen and state, its layout, components, content, and behavior notes.
- `copy.md`: the final English and Amharic strings with keys.
- `artifacts/`: the HTML source of each approved screen artifact (download or copy the code). Claude Code reads exact sizes and colors from these.
- `screens/`: a screenshot of each approved screen in both languages, for reference.

**Sprint exit:** the handoff package is merged on `main` (through a PR, so Opus checks that the files are complete and consistent with each other), with the Amharic copy reviewed.
