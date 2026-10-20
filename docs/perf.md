# Performance check (p95 under 300 ms)

Targets (`docs/architecture.md` §9): p95 under 300 ms for `GET /v1/packs`, `GET /v1/leaderboard` and `POST /v1/sessions`.

**Status: the tooling, the query-plan check and the write budget are done. The staging p50/p95/p99 run is not.** It needs a deployed staging Worker and a Firebase project, which this repository's CI and sessions do not have. The steps are in `ops/load/README.md`, and the results table below is empty until someone runs it. Do not read the SQL timings as route latency.

## What was measured here

### 1. Query plans on a full-size database (done)

`api/scripts/seed-perf.ts` filled a local D1 with the volume the task asks for: 1,000 tracks, 20,000 users, 300,000 sessions (about 1.5 KB of events each) and 83,000 leaderboard rows (all-time, plus 8 weeks, by era). (That run's `events_json` was malformed by a bug in the script, since fixed; it did not change row sizes or plans.) `EXPLAIN QUERY PLAN` for each route's SQL:

| Route | Plan |
|---|---|
| `/v1/packs` | scan of `packs` on `packs_slug_unique`, then a covering-index search of `pack_versions` per pack (5 packs) |
| `/v1/leaderboard` | `leaderboard_period_gen_points_idx` (period, era, points DESC), then one primary-key lookup of `users` per entry read; the sort only orders ties |
| `POST /v1/sessions`, reads | `game_sessions` primary key; `tracks`, `artists` and `generations` by id from `json_each` |
| `POST /v1/sessions`, writes | one insert each into `users`, `leaderboard_entries`, `game_sessions` |

No full scan of `game_sessions`, `leaderboard_entries` or `users` anywhere, so no index or query change was needed.

### 2. SQL time on that database (`api/scripts/sql-bench.ts`)

The same statements the Worker runs, in SQLite on the local file, 500 iterations each. This is database time only, without D1's network hop, the Worker, auth or the JSON response.

| Statement | p50 | p95 | p99 |
|---|---|---|---|
| packs list | 0.02 ms | 0.06 ms | 0.15 ms |
| leaderboard top 100 (all-time, all eras) | 0.18 ms | 0.43 ms | 0.59 ms |
| leaderboard top 100 (this week, one era) | 0.15 ms | 0.21 ms | 0.26 ms |
| leaderboard/me rank | 0.18 ms | 0.69 ms | 0.77 ms |
| session: the two reads | 0.07 ms | 0.18 ms | 0.25 ms |
| session: the three writes | 0.16 ms | 0.24 ms | 0.29 ms |

The SQL is not where the 300 ms would go. What a player waits for is the round trips to D1 (a session makes 3 in sequence: the rate-limit bucket, the batch of two reads, the write batch; a fourth only when two requests race on the same session id), Firebase token verification (the signing keys are cached per isolate, so a cold isolate adds one fetch to Google), and the network. Those only show up on the real run.

### 3. D1 rows written per session (done, the write budget is wrong)

`api/test/sessions.test.ts` ("a typical session writes 20 D1 rows…") sums `meta.rows_written`, the number the free plan bills, which counts index entries as well as rows.

| Session | Rows written |
|---|---|
| New registered player, 10 rounds in an era | **20** (users 2, leaderboard 12, session 4, rate-limit bucket 2) |
| Returning registered player | **14** |

`docs/architecture.md` §9 budgeted about 6 rows per session by counting table rows only. Billed, a session costs more than twice that, so the free plan lasts about **3,000 DAU**, not 12–15k (§9 is corrected). At 2 sessions per player per day, 14 rows a session is 28 rows per player a day, so 100k rows a day covers about 3,400 players, less the nightly roll-up. Next step: plan to move to Workers Paid ($5/month) once the beta goes past about 2,500 DAU.

### 4. Database size (done, this is the first free-plan limit)

The seeded database is **648 MB**, 587 MB of it `game_sessions`: about 1.96 KB a row, most of it `events_json`. D1's Free plan caps a database at 500 MB (from memory; check the Cloudflare docs), so the full 300k-session seed does not fit a Free-plan staging database. Seed about 200k (`--sessions 200000`) there, or run staging on Workers Paid.

The same applies to prod. The nightly job now trims `events_json` of sessions older than 90 days to what is still read (each round's track, points and correctness, and the ads): 1.5 KB becomes 0.5 KB, so a row drops to about 0.96 KB (`api/src/cron/rollups.ts`, `api/test/eventsTrim.test.ts`). That slows growth but does not stop it:

| DAU (2 sessions each) | 90 days of full rows | Then grows by | 500 MB reached after |
|---|---|---|---|
| 500 | 176 MB | 1 MB / day | about a year |
| 1,000 | 353 MB | 1.9 MB / day | about 5 months |
| 2,000 | (over 500 MB) | | about 2 months |

So storage, not writes, is the first free-plan limit: plan Workers Paid (10 GB per database) once the beta is past about 1,000 DAU. The trim runs on at most 5,000 sessions a night (one statement) and only looks at a 7-day band past 90 days, so a band the job missed for more than a week stays untrimmed.

## Load model

`ops/load/mix.js` (k6): 70 % leaderboard reads, 20 % session posts (10 rounds, valid, from 100 registered players so the leaderboard rows are written), 10 % pack lists. The players are reused Firebase accounts (`perf-<n>@example.com`): the first run creates them, later runs only sign in.

2,000 DAU peak hour, from these assumptions: 2 sessions per player per day, a quarter of the day's sessions in the peak hour, so about 1,000 session posts an hour. Sessions are 20 % of requests, so about 1.4 requests a second; the test uses **2 rps**. It then runs 5x (10 rps) and 10x (20 rps) to show headroom.

Leaderboard reads are the worst case: the Cache API only works on a custom domain (`docs/ops.md`), so on a `workers.dev` staging URL every read goes to D1. Production on its custom domain serves most from the edge cache.

## Results (staging run, to fill in)

Date:
Staging URL and region:
k6 version:

| Route | Stage | Requests | p50 | p95 | p99 | Error rate | Target met |
|---|---|---|---|---|---|---|---|
| packs | x1 (2 rps) | | | | | | |
| packs | x5 | | | | | | |
| packs | x10 | | | | | | |
| leaderboard | x1 | | | | | | |
| leaderboard | x5 | | | | | | |
| leaderboard | x10 | | | | | | |
| sessions | x1 | | | | | | |
| sessions | x5 | | | | | | |
| sessions | x10 | | | | | | |

If a route misses its target: run `EXPLAIN QUERY PLAN` for its statements on the staging D1 (`wrangler d1 execute yz-db-staging --env staging --remote --command "EXPLAIN QUERY PLAN ..."`), fix with an index or a query change, and re-run. Record what changed here.
