# Ops

## Admin authentication (Cloudflare Access)

Admin routes (`/admin/*`) and the admin SPA sit behind Cloudflare Access. The
Worker **also** verifies the `Cf-Access-Jwt-Assertion` header itself and checks
the caller against `admin_users` (`api/src/lib/accessAuth.ts`). This is defense
in depth: a misconfigured Access rule still can't reach the catalog or royalty
data.

### One Access application, two destinations

Create **one** self-hosted application under **Zero Trust → Access → Applications**, in the team
`ACCESS_TEAM_DOMAIN` (e.g. `https://yz.cloudflareaccess.com`), with both destinations:

- `admin.<domain>` (the SPA on Pages)
- `api.<domain>/admin/*` (the Worker's admin and ingest routes)

Policies:

1. **Admins**: allow the admin emails (one-time PIN, or Google). Humans log in through this.
2. **Ingest**: a Service Auth policy that allows the ingest **service token** (below), so GitHub
   Actions can reach `/admin/ingest/*`.

It has to be **one** application, for two reasons:

- **The SPA calls the API cross-origin.** The browser only sends the `CF_Authorization` cookie
  for `api.<domain>` if the user has one for that hostname. When an application has five or fewer
  domains, Access sets the cookie on all of them during the first login. A separate API
  application would never get a cookie from the admin login, so every SPA call would be
  redirected to the login page and fail CORS.
- **The Worker verifies a single audience.** Each Access application has its own **Application
  Audience (AUD) tag**. Put this application's tag in the `ACCESS_AUD` Worker var (and in
  `[env.prod.vars]`). The Worker checks that `iss` equals the team domain, that `aud` includes
  `ACCESS_AUD`, and `exp`, against the team JWKS at `${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`.

The Ingest policy also lets the service token fetch the SPA's static files. That's harmless:
the SPA holds no data, and service tokens never satisfy the human `requireAdmin` routes.

### CORS preflight

Every SPA request with a JSON body sends an `OPTIONS` preflight first. Browsers never attach
cookies to preflights, so Access blocks them by default. In the application, open **Configure →
Advanced settings → Cross-Origin Resource Sharing (CORS) settings** and turn on **Bypass OPTIONS
requests to origin**. The Worker answers preflights itself (`api/src/lib/cors.ts`), and only for
`ADMIN_ORIGIN`. Leave Access's own CORS header fields empty: the bypass replaces them.

**When an admin's Access session expires**, the next API call is redirected to the Access login
page. That redirect fails CORS, so the SPA can't tell it apart from a network failure. Its error
notification therefore asks the admin to reload the page, which goes through the login again.

### Service token for ingestion

GitHub Actions authenticates as a machine, not a person:

1. **Zero Trust → Access → Service Auth → Service Tokens** → create one (e.g.
   `yz-ingest`). Cloudflare gives a **Client ID** (ends in
   `.access`) and a **Client Secret** (shown once).
2. Add it to the **Ingest** policy on the Access application (above).
3. Set the Worker var `INGEST_SERVICE_CLIENT_ID` to the token's **common name**
   (the Client ID value that appears as the `common_name` claim).
4. Store the Client ID and Secret as GitHub Actions secrets; the workflow sends
   them as `CF-Access-Client-Id` / `CF-Access-Client-Secret` headers, and Access
   mints the JWT the Worker verifies.

`requireService()` accepts a request only when the verified JWT's `common_name`
equals `INGEST_SERVICE_CLIENT_ID`. Human (email) tokens never satisfy it, and
service tokens never satisfy the human `requireAdmin` routes.

### Seeding admins

```
cd api
npx tsx scripts/add-admin.ts you@example.com admin     # local D1
npx tsx scripts/add-admin.ts you@example.com editor -- --remote  # prod D1
```

Roles are `admin` and `editor`. Re-running updates the role.

### Local development

Running the Worker locally has no Access in front of it. Set `DEV_ADMIN_EMAIL`
in `api/.dev.vars` (gitignored; see `.dev.vars.example`) to an email you've also
added with `add-admin.ts`. When `ENV=dev`, a request with no Access header is
then treated as that admin. With `DEV_ADMIN_EMAIL` unset, `/admin/*` returns 401
even in dev. This bypass never applies when `ENV=prod`.

## Ingest jobs and workflows

Scraping and cutting run as GitHub Actions workflows, started from the Worker and tracked in `ingest_jobs`.

```
admin  --POST /admin/jobs-->  Worker: insert job (queued) --dispatch--> GitHub: ingest-scrape.yml | ingest-cut.yml
                                                                          |
        job: queued -> running -> succeeded | failed  <--status calls--  the run (yz.scrape / yz.cut)
```

- **Start a job**: `POST /admin/jobs { kind, params }` (any signed-in admin or editor), `GET /admin/jobs` for the last
  50, newest first. `kind` and `params` (anything else is a 400):

  | kind | params | workflow and arguments |
  |---|---|---|
  | `scrape` | `{ limit?, since? }` (`since` is `YYYY-MM-DD`) | `ingest-scrape.yml` with inputs `limit`, `since` |
  | `cut` | `{ trackIds: [..] }` or `{ allMissing: true, limit? }`, plus optional `type` | `ingest-cut.yml`, `--track-ids 1,2` or `--all-missing [--limit N]`, `--type T` |
  | `recut` | `{ trackId, type, startMs }` | `ingest-cut.yml`, `--track-id N --type T --start-ms M` |

  The arguments are built by the Worker from these validated values, never copied from the request.
  The answer is 201 with the job. If GitHub will not start the workflow, the job is kept as `failed` with
  GitHub's reason in its summary and the request is a 502 `dispatch_failed` that names the job.
- **A clip's start time** (`PATCH /admin/clips/:id`) saves the start, sets the clip `pending`, and starts a `recut`
  job for it. The response carries the job. If the job cannot be started the edit is still saved (the job is
  recorded as `failed`) and the clip stays `pending`, so the next `cut` with `allMissing` picks it up.
- **Scheduled scrape**: Mondays 03:17 UTC, looking back 30 days. A run with no job (the schedule, or started by
  hand) creates its own with `POST /admin/ingest/jobs`. Start one by hand from the Actions tab with empty inputs
  to try the pipeline.
- **Reporting**: each run posts `running` with a link to the Actions run, then `succeeded` or `failed` with a
  summary (the scraper's and cutter's counts). A step that runs on failure or cancellation marks the job `failed`
  if the run died before the scraper or cutter could say so (a bad argument, `pip` failing, a cancel). It never
  overrides a result the job already has.
- **Runs that cannot report for themselves**: scrape and cut share the concurrency group `ingest`, so one runs at
  a time. GitHub keeps only the **newest** waiting run and cancels older waiting ones before any step executes,
  so a job started while two others are ahead of it would stay `queued` for good. `ingest-watch.yml` catches
  this (and a run killed by a timeout or that never started): whenever an ingest run ends unsuccessfully it marks
  the job named in the run's title failed. A job whose run was cancelled this way is not retried; start it again,
  or start a `cut` job with `allMissing` to catch up on every pending clip.

### Setup

Repository secrets (GitHub: Settings > Secrets and variables > Actions) used by the three workflows:

| Secret | Value |
|---|---|
| `API_BASE` | the Worker's URL, e.g. `https://api.example.com` |
| `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` | the ingest service token (see above) |
| `R2_ENDPOINT` | `https://<account>.r2.cloudflarestorage.com` |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | an R2 API token that can read `yz-source` and write `yz-clips` |

Worker configuration:

| Name | Kind | Value |
|---|---|---|
| `GH_DISPATCH_TOKEN` | secret: `npx wrangler secret put GH_DISPATCH_TOKEN` (add `--env prod` for production) | the token below |
| `GH_REPO` | var in `wrangler.toml` | `owner/name` of this repository |
| `GH_REF` | var in `wrangler.toml` | the branch the workflows run from, `main` |

The Worker needs a token that can start workflows, and nothing more. Create a **fine-grained personal access
token** (GitHub: Settings > Developer settings > Personal access tokens > Fine-grained tokens):
resource owner = the account or org that owns the repository; **Repository access = Only select repositories**,
this repository alone; **Repository permissions = Actions: Read and write** and nothing else (GitHub adds
read-only Metadata itself); no account permissions; an expiry (set a reminder to rotate it). Tokens like this
cannot be broader than what you tick, and you can check it: with the token, `GET /repos/{owner}/{repo}/contents`
and any other repository both fail (403/404), while the workflow dispatch succeeds.

The workflows only exist for the dispatch API once they are on the branch named by `GH_REF`, so none of this
works until they are merged to `main`.

## Cutting clips (`ingest/`)

`python -m yz.cut` (run from `ingest/`, needs ffmpeg and the same environment variables as the scraper, with
`JOB_ID` a `cut` or `recut` job) turns each track's source audio into its two game clips, uploads them to the
public `yz-clips` bucket and registers them with the API:

```
python -m yz.cut --track-ids 1,2,3                           # both clips of these tracks
python -m yz.cut --all-missing [--limit 50]                  # every clip that is not ready yet
python -m yz.cut --track-id 7 --type intro --start-ms 41200  # recut one clip from a chosen start
```

`--type intro|middle` limits any of them to one clip. `R2_CLIPS_BUCKET` (default `yz-clips`) names the bucket;
the R2 token must be able to read `yz-source` and write `yz-clips`.

- **The clip**: 10 s, MP3 CBR 128 kbps, 44.1 kHz stereo, starting exactly at the start point (the cut is
  sample-accurate), with a 30 ms fade in and out and no metadata. Same source and start give the same bytes.
- **Start points**: the registered start is used if the clip exists (an admin's `PATCH /admin/clips/:id`
  stores their start and sets the clip `pending`, which is what makes `--all-missing` pick it up). Otherwise
  the intro starts at the first sound (leading silence below -40 dB for 0.3 s is skipped) and the middle at
  45 % of the source. A default is nudged earlier if it would leave less than 10 s; a start you give is never
  moved, and one that leaves less than 10 s is an error for that clip.
- **Keys and versions**: `clips/{trackId}/{type}-v{version}.mp3`, uploaded with
  `Cache-Control: public, max-age=31536000, immutable`. A clip identical to the registered one is skipped
  entirely; a different one goes to `version + 1`. Registered objects are never rewritten. See
  `docs/ingest-api.md` for the rule.
- **Problems with the source** are reported as review items on the track, in the same call that registers the
  clips (`flags` on `POST /admin/ingest/clips`): `missing_audio` when the track has no source key or the file
  is not in `yz-source`, `short_audio` when it is under 25 s. A source of 10 s or more is still cut; a shorter
  one cannot be, and counts as an error. Re-running does not duplicate the review items.
- **Length**: every finished clip is measured with ffprobe and must be 10.0 s +/- 30 ms, or it is not
  uploaded. MP3 is framed in 26.1 ms frames, so ffprobe reports whole frames: encoding exactly 10.000 s gives
  384 frames = 10.031 s, just outside the tolerance, so the cutter encodes 9.975 s (383 frames = 10.005 s by
  ffprobe, 9.975 s decoded). The registered `lengthMs` stays the nominal 10000.
- **Song length**: the cutter measures every source it downloads and records the length on the track (in the same
  call that registers the clips), when it is new or has changed. The scraper cannot know it, and moving a clip's
  start time needs it, so until a track has been through a cut its clips cannot be moved (`409 duration_unknown`).
  A source too short to cut still has its length recorded.
- **Job status** works as for the scraper, with a summary of `tracks`, `created`, `updated`, `unchanged`,
  `flagged`, `durations` and `errors`. A track that cannot be cut counts as an error and the run carries on; a storage or
  API failure fails the job.

## Running the scraper (`ingest/`)

`python -m yz.scrape` (run from `ingest/`) scrapes ethiozeima.com, uploads each MP3 to the private
`yz-source` bucket as `source/{sha1(source_url)}.mp3`, and posts track metadata to
`POST /admin/ingest/tracks` in batches of 100. It reads these environment variables (the
`ingest-scrape` workflow, P1S2 task 6, will supply them from GitHub secrets):

| Variable | Meaning |
|---|---|
| `API_BASE` | Worker base URL, e.g. `https://api.example.com` |
| `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` | the ingest service token (see above) |
| `R2_ENDPOINT` | `https://<account>.r2.cloudflarestorage.com` |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | an R2 API token with read/write on `yz-source` |
| `JOB_ID` | the `ingest_jobs` row (kind `scrape`) this run reports to |
| `R2_BUCKET` | optional, defaults to `yz-source` |
| `SCRAPE_DELAY`, `YZ_USER_AGENT` | optional: seconds between requests (default 2) and the User-Agent |

Options: `--limit N`, `--since YYYY-MM-DD`, `--dry-run`, `--delay S`, `--batch-size N`, `--fresh`.

- **Dry run** (`--dry-run`) needs no credentials. It reads the site, writes the records it would send to
  `ethiozeima_data/dry-run.jsonl`, and downloads, uploads and posts nothing.
- **Job status**: `running` at the start, then `succeeded` or `failed` with a summary
  (`scraped`, `created`, `updated`, `flagged`, `errors`, plus audio counts and up to 20 error messages).
  A post that cannot be fetched or has no Fidel artist name counts as an error and is skipped; a post
  with no MP3, or whose download fails, is still sent, flagged `missing_audio`. Storage or API failures
  fail the whole job.
- **Transliteration** (`yz/transliterate.py`): a post with only one script gets the other generated.
  Fidel -> Latin is deterministic (ሰላም -> `selam`). Latin -> Fidel is a guess with a confidence; below 0.8 the
  track gets a `translit_uncertain` review item. A post with both scripts is checked too: if the Latin differs
  from the Latin generated from the Fidel by a normalized edit distance over 0.3 (after ignoring doubled letters,
  q/k and ph/f), it is flagged, so a wrong pairing or a translated title lands in the queue. The source Latin is
  always kept as an alias of the artist.
- **Duplicate detection** (`yz/dedupe.py`): before posting, a real run fetches `GET /admin/ingest/catalog-snapshot`
  once and checks each record against it and against earlier records in the same run. It never merges:
  an exact normalized match (homophones folded) is the same artist, but a fuzzy artist match (edit-distance
  ratio ≥ 0.85, token-order-insensitive) or a matching track title (≥ 0.9, within the resolved artist) only
  adds a `possible_duplicate` review item with candidate IDs and scores. Live/remix/cover titles are flagged
  with a `variant_of` hint; a duration gap over 15% lowers the score. Thresholds are tunable constants at the
  top of `dedupe.py`. A dry run has no snapshot, so it only finds within-batch duplicates.
- **Re-runs are cheap**: audio already in R2 with the size the site reports is neither downloaded nor
  re-uploaded, and the API treats a repeated batch as a no-op.
- **Resume**: after each posted batch the last URL goes to `ethiozeima_data/checkpoint.json`. A re-run after
  a crash continues after it (the archive is newest first, so posts published in between are picked up
  by the next full run); `--fresh` ignores it. A run that finishes removes it.
- **Local testing**: the ingest routes always require a verified Access JWT, and the `DEV_ADMIN_EMAIL`
  bypass covers human admin routes only, so the scraper cannot post to `wrangler dev` directly.
  `api/test/ingest.test.ts` covers the API side; `ingest/tests/` covers the scraper with fakes.

## Admin SPA on Cloudflare Pages

The admin SPA (`admin/`) is a static Vite build hosted on Cloudflare Pages at `admin.<domain>`, behind the
Access application above. Configure the Access application (both destinations and the OPTIONS bypass) before the first
deploy. Without it, every API call fails CORS.

**Pages project settings** (Workers & Pages → Create → Pages → Connect to Git):

| Setting | Value |
|---|---|
| Production branch | `main` |
| Root directory | `admin` |
| Build command | `npm ci && npm run build` |
| Build output directory | `dist` |
| Environment variable | `VITE_API_BASE=https://api.<domain>` (Production **and** Preview) |

`VITE_API_BASE` is required: `npm run build` fails without it, so a misconfigured Pages project fails its deploy
instead of shipping a site that calls `localhost`.

**Worker side:** the Worker must allow the admin origin for CORS. `ADMIN_ORIGIN` in `api/wrangler.toml`
(`[env.prod.vars]`) is set to `https://admin.<domain>`. Replace the `admin.example.com` placeholder before the
first prod deploy, otherwise the browser gets no `Access-Control-Allow-Origin` header and every admin call fails.

**Local development:** run `npm run dev` in `api/` (port 8787) and `npm run dev` in `admin/` (port 5173). Use
`localhost`, not `127.0.0.1`, because `ADMIN_ORIGIN` is `http://localhost:5173`.
