# Yeman Zefen (የማን ዘፈን)

A free, ad-supported "guess the song" game for Amharic music. A player hears a short clip, from the intro or the middle of a song, and picks the song or artist from four options.

It runs on Android and iOS from one Flutter codebase, in Amharic or English. Clips play straight away, upcoming clips download in the background, and players can download song packs to play offline. The catalog is curated by admins and fed by a Python scraper, so every track is reviewed before players see it.

## Repository layout

| Folder | What it is | Stack |
|---|---|---|
| [`api/`](api/) | The game API and admin API | Cloudflare Worker, TypeScript, Hono, zod, Drizzle on D1, R2 |
| [`admin/`](admin/) | Admin dashboard for the catalog, review queue and packs | Vite, React, Mantine, TanStack Query |
| [`app/`](app/) | The player app (Android and iOS) | Flutter, drift, just_audio, Firebase Auth |
| [`ingest/`](ingest/) | Scraper and clip cutter that feed the catalog | Python, ffmpeg, GitHub Actions |
| [`docs/`](docs/) | Product, architecture, API and ops notes, plus the sprint task prompts | Markdown |

Each folder has its own README with commands and local setup where it has one: [`api/`](api/), [`admin/README.md`](admin/README.md), [`app/README.md`](app/README.md), and [`ingest/`](ingest/).

## Documentation

- [Product requirements (PRD)](docs/prd-amharic-music-game.md)
- [Architecture and roadmap](docs/architecture.md)
- [Scoring rules](docs/scoring.md) and [session payload](docs/session-payload.md)
- [Ingest API](docs/ingest-api.md) and [pack manifest](docs/pack-manifest.md)
- [Ops: Cloudflare Access, deploys and secrets](docs/ops.md)
- [Design system and screens](docs/design/README.md)

## Getting started

You need Node 22 for `api/` and `admin/`, Flutter 3.47 for `app/`, and Python 3.12 with ffmpeg for `ingest/`.

### API

```sh
cd api
npm ci
npm run dev                      # wrangler dev, with local D1 and R2
npm run typecheck && npm test
npm run db:migrate:local         # apply migrations to local D1
```

Put local secrets in `api/.dev.vars`. That file is gitignored. Never commit secrets or put them in `wrangler.toml`; use `wrangler secret put` for deployed values.

### Admin

```sh
cd admin
npm ci
npm run dev                      # http://localhost:5173, needs the API running
npm test
```

### App

```sh
cd app
flutter pub get
flutter run --flavor dev --dart-define-from-file=config/dev.json
flutter analyze && flutter test
```

The app refuses to start without `--dart-define-from-file`. See [`app/README.md`](app/README.md) for running on a real phone.

### Ingest

```sh
cd ingest
pip install -r requirements.txt pytest
python -m yz.scrape --dry-run    # scrape to a local JSONL file, upload nothing
python -m yz.cut --all-missing   # cut clips for tracks that lack one
pytest
```

The scraper and cutter normally run on GitHub Actions (`.github/workflows/ingest-*.yml`), started by the API.

## Checks

CI (`.github/workflows/ci.yml`) runs on every pull request and on pushes to `main`:

- **api**: typecheck, then tests
- **admin**: typecheck, tests and a production build
- **app**: `flutter analyze` and `flutter test`
- **ingest**: `pytest`
- **workflows**: `actionlint` on the GitHub workflow files

## Contributing

Work is split into small tasks, one per pull request. Each task lives in a `docs/phase-*-sprint-*-prompts.md` file. Branches are named `task/p<phase>s<sprint>-<slug>`, for example `task/p1s1-scaffold`. Never push directly to `main`. The PR template is at [`.github/pull_request_template.md`](.github/pull_request_template.md).

## Status

The project is in active development. The roadmap, with phases and exit criteria, is in [`docs/architecture.md`](docs/architecture.md#roadmap).
