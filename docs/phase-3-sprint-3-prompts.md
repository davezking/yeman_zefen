# Phase 3 · Sprint 3 — Admin v2: reporting & moderation

> **Shipping each task:** branch `task/p<phase>s<sprint>-<slug>` → push → open a PR with the template → the Claude Opus review must return APPROVE before merging. The model tag on each task is for *writing* the code; review is always Opus.

Goal: the admin can export the royalty report for the music association, see core analytics, and handle suspicious scores.

---

## Task: Royalty usage report page + CSV export

**Model:** haiku — a query and a CSV over a roll-up table that already exists.

**Context:** `royalty_daily(date, track_id, plays)` is filled nightly. FR-22: per-track play counts for a date range, for the music association. The admin SPA has a placeholder `/reports` route.

**Do this:**
1. `GET /admin/reports/royalty?from=YYYY-MM-DD&to=YYYY-MM-DD&format=json|csv`: sum plays per track in the range, joined to the Fidel title, Latin title, artist (am and latin), album, and release year. Sort by plays descending.
   - CSV is UTF-8 **with a BOM**, so Excel shows Fidel correctly, and has a header row.
   - The filename includes the range.
   - Include a final total row.
2. `/reports` page: a date-range picker with presets (last month, last quarter), a preview table with totals, and a CSV download button. Show a note if the range includes today, which isn't rolled up yet.

**Before moving on, check:**
- The CSV opens in Excel and Google Sheets with Fidel intact.
- The report's total equals the sum of `royalty_daily` for the range.

---

## Task: Analytics dashboard

**Model:** sonnet — cohort retention needs careful SQL; the rest is charting.

**Context:** `analytics_daily` holds `dau`, `new_users`, `sessions`, `rounds`, `rounds_per_session`, and `plays_by_country`. Retention isn't rolled up yet. FR-23 also lists installs and ad metrics. Installs aren't in our data, so use `new_users` as the proxy, labeled clearly. Ad metrics come from `ad_events_daily`. PRD targets: D1/D7/D30 retention of 35 % / 15 % / 6 %, 1,000 DAU by month 3, and ≥ 15 rounds per session.

**Do this:**
1. Extend the nightly cron to compute D1, D7, and D30 retention for each cohort date: users created on day X who have a session on day X+1, X+7, or X+30. Write them as `analytics_daily` metrics keyed by the cohort date.
2. `GET /admin/analytics?from&to` returns the series.
3. `/analytics` page (use `@mantine/charts`):
   - KPI cards against the PRD targets.
   - DAU and new-user lines.
   - Rounds per session.
   - A retention table by cohort week.
   - Top countries, with a "diaspora share" figure (plays outside ET).
   - Ad impressions and rewarded completions.
   - Links out to Play Console, App Store Connect, and AdMob for official install and revenue figures.

**Before moving on, check:**
- Retention computed on seeded test data matches a hand-checked case.
- Every KPI card shows its target and whether it's being met.

---

## Task: Anomaly detection pass in the nightly cron

**Model:** sonnet — statistical thresholds and safe flagging, with no automatic punishment.

**Context:** Sessions are already flagged inline for hard sanity violations. R-5 adds pattern checks: score velocity, accuracy far outside the norm, and too-regular timing. Leaderboards exclude flagged sessions at write time. This pass looks across the previous day and flags users for human review; it never bans anyone automatically.

**Do this:**
1. In the nightly cron, per registered user active yesterday, compute: sessions per hour (max), accuracy, median `responseMs`, the coefficient of variation of `responseMs`, and the share of hard-difficulty sessions.
2. Flag a user (insert `review_items` with `entity_type = 'user'` and reason `score_anomaly`, plus the metrics in details) if any holds:
   - accuracy ≥ 98 % over ≥ 50 rounds with median response < 900 ms;
   - CV of response < 0.1 over ≥ 30 rounds (bot-like regularity);
   - ≥ 20 sessions in any single hour;
   - weekly points above the 99.9th percentile *and* ≥ 3× the next-highest player.
3. Put thresholds in constants with one-line rationales.
4. Tests with synthetic honest, bot-like, and elite-but-human players. The elite-human case must not be flagged by the regularity rule.

**Before moving on, check:**
- No automatic bans or score changes; this pass only flags.
- Reruns for the same day don't duplicate open flags.

---

## Task: Moderation UI — flagged sessions, shadow-ban

**Model:** sonnet — a moderation action affects leaderboards, so its side effects must be correct.

**Context:** Flags come from inline session checks (`game_sessions.flagged`) and nightly anomaly flags (`review_items` with reason `score_anomaly`). `users.shadow_banned` hides a user from others' leaderboards.

**Do this:**
1. API:
   - `GET /admin/moderation/users/:id`: profile, recent sessions with per-round details, and flags.
   - `POST /admin/users/:id/shadow-ban { banned, note }`.
   - `POST /admin/sessions/:id/void`: sets flagged, subtracts its points from that user's leaderboard rows in one batch. Make it idempotent.
2. Shadow-banning takes effect on reads immediately (already filtered there). Unbanning leaves points intact.
3. `/moderation` page: a queue of anomaly flags and flagged sessions, a user drill-down with a response-time histogram, and ban, void, and dismiss actions with a required note. Log moderation actions to a new `moderation_log` table (add a migration).

**Before moving on, check:**
- Voiding a session twice subtracts its points only once.
- A shadow-banned user disappears from the public top 100 within the 60 s cache window.
- Every action records who did it and why.
