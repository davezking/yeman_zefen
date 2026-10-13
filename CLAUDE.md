# Yeman Zefen (የማን ዘፈን)

A free, ad-supported "guess the song" game for Amharic music. It plays offline from downloadable packs, and its catalog is curated by admins and fed by a Python scraper.

The architecture doc is `docs/architecture.md`. Read only the section a task names. Task prompts are in `docs/phase-*-sprint-*-prompts.md`.

## Layout
- `api/`: Cloudflare Worker (TypeScript, Hono, zod, Drizzle on D1, R2). Routes in `src/routes/`, helpers in `src/lib/`, tests in `test/`, SQL in `migrations/`.
- `admin/`: Vite + React admin SPA (placeholder).
- `app/`: Flutter app (placeholder).
- `ingest/`: Python scraper (`ethiozeima_scraper.py`) and ffmpeg clip cutter (`clip_maker.py`), tests in `tests/`.
- `docs/`: architecture, task prompts, ops notes.
- `.github/workflows/`: CI (`ci.yml`).

## Commands
| Package | Dev | Test | Deploy |
|---|---|---|---|
| `api/` | `npm run dev` (wrangler dev, local D1/R2) | `npm run typecheck && npm test` | `npm run deploy` (`--env prod`); `npx wrangler d1 migrations apply yz-db` |
| `api/` schema | edit `src/db/schema.ts`, then `npm run db:generate` | `npm run db:migrate:local` | commit the generated `migrations/` (incl. `meta/`) |
| `ingest/` | `pip install -r requirements.txt pytest` | `pytest` | runs on GitHub Actions |

## Conventions
- TypeScript `strict`. No `any` without a comment saying why.
- Validate every request body (and query/params) with zod before use.
- Timestamps are integer epoch milliseconds, UTC.
- Errors are always `{ "error": { "code": "snake_case", "message": "..." } }`. Throw `ApiError` from `api/src/lib/errors.ts`.
- No secrets in code or `wrangler.toml`. Use `wrangler secret put` and `api/.dev.vars` (gitignored).
- D1 query budget: the Free plan allows 50 D1 queries per request and each statement in a `batch()` counts, so a request's query count must not grow with the number of records. Use set-based SQL (`json_each`) for bulk writes. See `docs/ingest-api.md` and `test/queryBudget.test.ts`.
- Python: standard library + `requests`/`beautifulsoup4`. Keep the scripts runnable directly.

## Git workflow
- One branch per task: `task/p<phase>s<sprint>-<slug>` (e.g. `task/p1s1-scaffold`).
- Small commits with clear messages, then push.
- Open a PR with `gh pr create`, using the PR template. Fill in the task, model used and checklist.
- Never push directly to `main`.
