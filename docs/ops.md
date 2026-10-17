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

## Clip editor: source audio URLs

`GET /admin/tracks/:id/source-url` returns a presigned, 10-minute read URL for a track's audio in the private
`yz-source` bucket; the clip editor feeds it to wavesurfer.js. One-time setup:

1. Set the vars `R2_ENDPOINT` (`https://<account>.r2.cloudflarestorage.com`) and, if the bucket is not
   `yz-source`, `R2_SOURCE_BUCKET`.
2. `wrangler secret put R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` (per env) with an R2 API token that has
   read access to `yz-source`. Without them the route answers 503 `source_signing_unconfigured`.
3. Add a CORS rule on `yz-source` allowing `GET` and `HEAD` (header `Range`) from the admin origin, since the
   browser fetches the file straight from R2.

Under `wrangler dev` there is no S3 endpoint for the local bucket, so the waveform only loads against real R2
credentials; the rest of the page works without it.

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

### Track editor API

The admin track table and editor (`/tracks`, `/tracks/:id`) use these routes, all behind `requireAdmin` (editors
and admins alike):

| Route | Purpose |
|---|---|
| `GET /admin/tracks` | List, newest first, 50 per page (`cursor`). Filters: `status`, `generationId` (era), `genreId`, `artistId`, `q` (either title). Each row also carries `introStatus` / `middleStatus` (`null` = clip not cut yet) and `openFlagCount`. |
| `GET /admin/tracks/:id` | Track, artist, aliases, `genreIds`, open review items, and clips. A clip has a `url` only while it is `ready`. |
| `PATCH /admin/tracks/:id` | Edit titles, album, year, era, artist and `genreIds` (replaces the whole set, at most 10). Send only what changed: every field sent is pinned against re-scrapes. Picking an era pins it; clearing it (`generationId: null`) re-derives it from the year, as does changing the year of an unpinned track. An edit that leaves the era unknown opens an `era_unknown` item (and sends an `ingested` track to `needs_review`); one that makes it known resolves the open item. |
| `POST /admin/tracks/:id/approve`, `/reject` | `409 clips_not_ready` names the clip that is missing or not ready; `409 invalid_transition` means the status does not allow it. |
| `GET /admin/generations`, `GET /admin/genres` | The era and genre lists for pickers and filters. |
| `POST /admin/artists` | Create an artist (and its canonical alias), atomically. `409 artist_exists` names the artist when the spelling folds to a known name or alias, including one created at the same moment. |
| `POST /admin/review-items/:id/resolve`, `/dismiss` | Close an open item, recording who and when. `409 already_closed` if it is not open. |

**Playing clips locally.** `CDN_BASE_URL` points at `http://localhost:8787/cdn` in dev, and under `wrangler dev` the
Worker serves `GET /cdn/clips/*` from the local `yz-clips` bucket (with byte ranges, so the player can seek). The
route answers 404 unless `ENV=dev`: in prod the CDN domain serves the bucket directly. To try the editor with audio,
put a file at a clip's key: `npx wrangler r2 object put yz-clips/clips/1/intro-v1.mp3 --file clip.mp3 --local`.

### Review queue API

The review queue (`/review`) works through the open `review_items` that ingest and the cutter raise, one reason per tab.
Only items about tracks are listed: that is all the pipeline raises.

| Route | Purpose |
|---|---|
| `GET /admin/review-items` | Oldest first (by id), 50 per page (`cursor`). Filters: `reason`, `status` (`open` by default). Each item has its `track` (titles, artist names, year, era, status, length, source) and its `details` parsed from JSON (`null` if it is not JSON). |
| `GET /admin/review-items/counts` | Open items per reason, `0` for reasons with none. |
| `POST /admin/review-items/:id/resolve`, `/dismiss` | Close an open item. *Resolve* means the problem was dealt with; *dismiss* means it was not a problem. |
| `POST /admin/tracks/:id/mark-duplicate` `{ canonicalTrackId }` | Reject the track and link it to the canonical one (`tracks.canonical_track_id`). Nothing is deleted. In the same step its open `possible_duplicate` items are resolved and its other open items dismissed. Only `ingested` or `needs_review` tracks, and the canonical track must be `ingested`, `needs_review` or `approved` (`409 canonical_not_usable`). Links stay one level deep: `409 canonical_is_duplicate` if the target is itself a duplicate, `409 has_duplicates` if other tracks point at this one. These rules are also guards in the update itself, so two admins at once cannot make a chain or a cycle. |

What each tab shows, from the flag's `details` (written by `ingest/yz/`):

| Reason | `details` | Panel |
|---|---|---|
| `translit_uncertain` | `{ field: "artist" \| "title", source, generated, confidence? \| distance? }`. With `confidence`, `generated` is Fidel made from the source Latin; with `distance`, it is Latin made from the source Fidel. | The stored Fidel and Latin are editable, beside the source and generated text. Accepting saves what changed (the track's title, or the artist's name everywhere) and resolves the item. |
| `possible_duplicate`, `field: "track"` | `{ field, candidates: [{ id \| sourceUrl, score, durationDiff? }], variant_of? }` | The incoming track beside each candidate, with players. *Same song* marks it as a duplicate (above); *different* dismisses. |
| `possible_duplicate`, `field: "artist"` | same, with artist candidates | *Same artist* merges the track's artist into the candidate (`POST /admin/artists/:id/merge`, **admins only**), then resolves. *Different* dismisses. |
| `era_unknown` | none | A year and/or an era. Saving settles the item through `PATCH /admin/tracks/:id`. |
| `missing_audio`, `short_audio` | free-form (`cause`, `key`, `durationMs`) | *Re-run cut* starts a `cut` job for the track and resolves the item (a cut that still fails raises a new one). Retire (approved track) or reject (any other: the status machine has no retire for them) takes the track out, which closes its items. *Dismiss* when the audio is fine. |

A candidate that was scraped in the same batch has only a `sourceUrl` until it is ingested, so it cannot be merged or
linked to: the panel says so. Closing the last open item of a track offers to approve it.

**Taking a track out closes its items.** Rejecting or retiring a track (`/reject`, `/retire`, and mark-duplicate)
dismisses all of its open review items in the same batch, recording who did it: a track out of the catalog has nothing
left to review. It also stays closed: ingest and the cutter open no new items about a rejected or retired track (a
re-scrape reports it `skipped`), an era edit on one opens no `era_unknown` item, and the queue and its counts leave such
tracks out. Mark-duplicate records only the song-duplicate flag (`field: "track"`) as resolved; an artist-duplicate
flag on the same track is dismissed, since nobody looked at the artists.

**A track others are duplicates of cannot be rejected** (`409 has_duplicates`): that would leave no copy of the song.
Retiring an approved one is allowed, since that takes the song out on purpose.

## Firebase (player identity)

Every player, guests included, signs in with Firebase Auth. The app signs in
anonymously on first launch with no UI. Guests link Google, email or Apple later
(the linking UI is Phase 3 Sprint 2), which keeps the same UID.

### Projects and app ids

One Firebase project per flavor:

| Flavor | Firebase project id | Android package | iOS bundle id |
|---|---|---|---|
| `dev` | `yman-zefen-dev` | `com.yemanzefen.yeman_zefen.dev` | `com.yemanzefen.yemanZefen.dev` |
| `prod` | `yeman-zefen-prod` | `com.yemanzefen.yeman_zefen` | `com.yemanzefen.yemanZefen` |

(The dev project id is spelled `yman`; Firebase project ids can't be renamed.)

The Worker verifies ID tokens against the project id (`iss = https://securetoken.google.com/<project>`,
`aud = <project>`), so its `dev` environment must use `yman-zefen-dev` and `prod` must use `yeman-zefen-prod`.

### One-time setup

1. Install the tools: Flutter, Node.js, then
   `npm i -g firebase-tools` and `dart pub global activate flutterfire_cli`.
   Put the npm global folder and the pub cache (`~/.pub-cache/bin`, or
   `%LOCALAPPDATA%\Pub\Cache\bin` on Windows) on `PATH`. Run `firebase login`.
2. In the [Firebase console](https://console.firebase.google.com) create both
   projects. In each, open Build > Authentication > Sign-in method and enable
   **Anonymous**, **Google**, **Email/Password** and **Apple** (Apple needs an
   Apple Developer account: services id, key and team id; it can wait for the
   linking sprint).
3. In each project, add the debug **SHA-1 and SHA-256** fingerprints of the
   Android app (`cd app/android && ./gradlew signingReport`), and later the
   release keystore's. Google sign-in on Android needs them.
4. Generate the Dart options, one file per flavor, from `app/`:

   ```
   flutterfire configure --project=yman-zefen-dev --out=lib/core/config/firebase_options_dev.dart \
     --android-package-name=com.yemanzefen.yeman_zefen.dev --ios-bundle-id=com.yemanzefen.yemanZefen.dev --platforms=android,ios
   flutterfire configure --project=yeman-zefen-prod --out=lib/core/config/firebase_options_prod.dart \
     --android-package-name=com.yemanzefen.yeman_zefen --ios-bundle-id=com.yemanzefen.yemanZefen --platforms=android,ios
   ```

5. **Move the Android file per flavor.** Each run writes
   `android/app/google-services.json`, and the second run overwrites the first.
   After each run, move it to `android/app/src/<flavor>/google-services.json`
   (`src/dev/` and `src/prod/`). Gradle's Google Services plugin picks the file
   from the flavor's source set, so a `dev` build never uses the prod project.
   A build that fails with "No matching client found for package name" means the
   flavor's file is missing or from the other project.
6. **iOS config file (needs a Mac).** `flutterfire` can't write the iOS native
   file from Windows. On a Mac, download `GoogleService-Info.plist` for each iOS
   app from the Firebase console and keep them at
   `app/ios/config/dev/` and `app/ios/config/prod/`, then add a Run Script build
   phase that copies the one for the active configuration into the app bundle.
   Until then the Dart options carry the iOS ids, which is enough for Auth;
   the plist is needed for Crashlytics and Google sign-in.

### What is committed

`firebase_options_{dev,prod}.dart`, `firebase.json` and the per-flavor
`google-services.json` files are committed. They hold public client
identifiers, not secrets: the Worker trusts only a verified ID token. Still,
restrict each API key to its app in Google Cloud Console > APIs & Services >
Credentials (Android package + SHA-1, iOS bundle id). Never commit a
service-account JSON; nothing in this project needs one.

### Which project the app uses

`lib/core/config/firebase_bootstrap.dart` picks the options from the `APP_FLAVOR`
build define (`--dart-define-from-file=config/<flavor>.json`).

### Checking it works

1. `flutter run --flavor dev --dart-define-from-file=config/dev.json`. A new
   anonymous user appears in the dev project under Authentication > Users.
2. Restart the app: the same UID.
3. Airplane mode on a fresh install: the game still starts and plays bundled
   clips. Turn the network on and the anonymous user appears without
   restarting.
4. Repeat for `--flavor prod` against the prod project.

## Nightly roll-ups

A Cron Trigger (`30 0 * * *`, UTC; `api/src/cron/rollups.ts`) rolls the previous UTC day of `game_sessions` up into the tables the admin site reads. A session belongs to the day its `received_at` (server clock) falls in: `[00:00:00.000, next 00:00:00.000)`.

| Table | Rows for a day |
|---|---|
| `royalty_daily` | one per track: every entry of `track_ids_json`, right or wrong, flagged sessions included. The day's total equals the sum of `json_array_length(track_ids_json)`. |
| `ad_events_daily` | per country and format: `interstitial`/`shown` and `rewarded`/`completed`, from `events_json.ads`. Zero counts are not stored. Unplaced sessions use country `XX`. |
| `analytics_daily` | `sessions`, `rounds`, `rounds_per_session` (**x100**, rounded: 175 = 1.75), `dau` (distinct users; deleted accounts count as one), `new_users` (`users.created_at` that day), and `plays_by_country` (dimension = country, value = tracks played). Always written, so a day with no sessions still has `sessions = 0`. |

- **Reruns are safe.** A run deletes the day's rows and inserts them again in one batch, so the result is the same however often it runs, and a failure leaves the day untouched.
- **Missed nights fill themselves.** Each run rolls up yesterday and any day of the last 7 with no `sessions` row, at most 6 days per run (Free plan: 50 D1 queries per invocation). A failing day does not stop the others; the run then fails visibly and the next one retries it. Each day logs `rollup <date>: sessions=.. rounds=.. royalty_rows=.. ad_rows=.. analytics_rows=..`.
- **Backfill or fix a day:** `POST /admin/rollups/run { "date": "2026-10-14" }` (admins only; the day must have ended, UTC). Answers with the same summary.
- **Prod:** `npm run deploy` registers the trigger (`[env.prod.triggers]`); the dev worker has none (try it with `wrangler dev --test-scheduled`). A play of a track id missing from `tracks` is left out of `royalty_daily` rather than failing the day.

## Remote config (`GET /v1/config`)

The app's tunables come from the Worker's vars: `CONFIG_INTERSTITIAL_EVERY_ROUNDS`, `CONFIG_REGISTER_PROMPT_AFTER_SESSIONS`, `CONFIG_REGISTER_PROMPT_COOLDOWN_DAYS`, `CONFIG_MIN_APP_VERSION` and `CONFIG_DEFAULT_CLIP_MS` (set in `api/wrangler.toml`). Change one and redeploy; the app picks it up on its next start.

- The endpoint is public and answers with `Cache-Control: public, max-age=600`.
- A var that is missing or not valid is a 500 `config_invalid` that names the var. The app then keeps its cached or built-in values, so check the var before deploying.
- `CONFIG_MIN_APP_VERSION` (`major.minor.patch`): an app older than it shows an "Update needed" screen instead of playing. Its store link is `STORE_URL` in `app/config/<flavor>.json`.

## Leaderboards (`GET /v1/leaderboard`)

- The top 100 per (period, generation) is cached for 60 s with the Workers Cache API. Responses tell the app to keep a board for 15 s, so a board is at most about 75 s old.
- **The Cache API works only when the Worker is served on a custom domain.** On `*.workers.dev`, `caches.default` stores nothing, so every request hits D1. Add a custom domain or route to `[env.prod]` in `wrangler.toml` before launch.
- `GET /v1/leaderboard/me` is not cached. Its rank is a count over the points index minus the hidden (shadow-banned or deleted) users above the caller, read through `users_hidden_idx` (migration 0007). Apply it with `npx wrangler d1 migrations apply yz-db`.
- Shadow-banning a user hides them from the cached board within about 75 s.

## Account linking (Google, email, Apple)

The app links a provider to the guest's Firebase user (`AccountLinker` in `app/lib/core/auth/account_linker.dart`). Linking keeps the uid, and the app then calls `POST /v1/me/registered`, which marks the user registered and rebuilds their leaderboard rows from their unflagged sessions. If the credential already belongs to another account, the app saves the guest's ID token, signs in to that account and calls `POST /v1/me/merge`. The server moves the guest's sessions to the account, deletes the guest row and rebuilds the account's rows. Both calls are safe to repeat. A server step that fails (offline) is kept in the `pending_account_sync` table and retried on the next start. The server accepts a guest token up to 30 days old for this. In practice the retry window is shorter: the token is still checked against Google's current signing keys, and Google drops a key from its JWKS some days after rotating it. A merge retried after that gets 401 `invalid_anonymous_token`, and the app stops retrying. The merge normally goes out straight after the sign-in, which needs the network anyway, so only a connection lost in that moment and not restored for days hits this.

Setup before these work on a device:
- **Firebase console → Authentication → Sign-in method:** enable Google, Email/Password and Apple.
- **Google on Android:** add the release and debug SHA-1 fingerprints to the Android app in Firebase. Set `GOOGLE_SERVER_CLIENT_ID` in `app/config/<flavor>.json` to the project's **Web** OAuth client id (Google Cloud → Credentials). With it empty, the app offers no Google button.
- **Google on iOS:** add the `REVERSED_CLIENT_ID` URL scheme from `GoogleService-Info.plist` to `ios/Runner/Info.plist`.
- **Apple:** turn on the *Sign in with Apple* capability for the iOS app in Xcode and the Apple Developer portal. Apple is offered on iOS only. Set `APPLE_ON_ANDROID` to `true` to offer it on Android, which also needs a Services ID and return URL.
- Merges are logged as `guest_merged` with both uids. Rejected guest tokens are logged as `merge_token_rejected`.
