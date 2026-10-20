# Load test (k6)

Measures p50/p95/p99 of `GET /v1/packs`, `GET /v1/leaderboard` and `POST /v1/sessions` on the staging Worker. Results go in `docs/perf.md`.

## One-time staging setup

1. `cd api`, then create the resources named in `wrangler.toml` under `[env.staging]`:
   `npx wrangler d1 create yz-db-staging`, `npx wrangler r2 bucket create yz-clips-staging`, `npx wrangler r2 bucket create yz-source-staging`. Put the new D1 id in `database_id`.
2. `npx wrangler d1 migrations apply yz-db-staging --env staging --remote`
3. `npx wrangler deploy --env staging`
4. Seed the volume (about 300k sessions; a few minutes): `npx tsx scripts/seed-perf.ts --db yz-db-staging --env staging --remote`. It refuses a database that already has tracks.
5. Firebase: staging verifies tokens from the **dev** Firebase project (`FIREBASE_PROJECT_ID` in `[env.staging.vars]`). In that project enable Email/Password sign-in, and copy the Web API key (Project settings, General).

## Run

```
k6 run -e BASE_URL=https://yz-api-staging.<account>.workers.dev \
       -e FIREBASE_API_KEY=<web API key> \
       --summary-trend-stats="avg,med,p(90),p(95),p(99),max" \
       ops/load/mix.js
```

`setup()` signs up 200 test players (`perf-<run>-<n>@example.com`) and uses their ID tokens, which last an hour; a full run takes about 17 minutes (three 5-minute stages). Options: `-e USERS=`, `-e BASE_RPS=2`, `-e STAGE_SECONDS=300`. The test accounts stay in the dev Firebase project; delete them in the console when done.

Each route has a p95 < 300 ms threshold, so k6 exits non-zero when one is missed. The `route` and `stage` tags split the summary per route and per stage (use `--out json=run.json` for the raw points). `rate_limited_429` counts rate-limit refusals; it should be 0 at this load.

## After the run

- Fill the table in `docs/perf.md`.
- Optionally confirm rows written per session on the real D1: `SELECT COUNT(*) FROM game_sessions` before and after, and the D1 "rows written" figure in the Cloudflare dashboard, against the 14 to 20 per session from `api/test/sessions.test.ts`.
- Re-check query plans with `npx tsx scripts/sql-bench.ts` against a local seeded DB (`seed-perf.ts --local`).
