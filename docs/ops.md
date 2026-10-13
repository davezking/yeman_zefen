# Ops

## Admin authentication (Cloudflare Access)

Admin routes (`/admin/*`) and the admin SPA sit behind Cloudflare Access. The
Worker **also** verifies the `Cf-Access-Jwt-Assertion` header itself and checks
the caller against `admin_users` (`api/src/lib/accessAuth.ts`). This is defense
in depth: a misconfigured Access rule still can't reach the catalog or royalty
data.

### Two Access applications

Create both under **Zero Trust → Access → Applications**, in the same team
(`ACCESS_TEAM_DOMAIN`, e.g. `https://yz.cloudflareaccess.com`):

1. **Admin SPA** — self-hosted app for `admin.<domain>`. Policy: allow the admin
   emails (one-time PIN, or Google). This is what humans log in through.
2. **Admin API** — self-hosted app for `api.<domain>/admin/*`. Same identity
   policy for humans, **plus** a policy that allows the ingest **service token**
   (below) so GitHub Actions can reach `/admin/ingest/*`.

Both applications must share one **Application Audience (AUD) tag**, or you need
one per app and must verify against the right one. Put that tag in the
`ACCESS_AUD` Worker var (and `[env.prod]`). The Worker checks `iss` equals the
team domain, `aud` includes `ACCESS_AUD`, and `exp`, against the team JWKS at
`${ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`.

### Service token for ingestion

GitHub Actions authenticates as a machine, not a person:

1. **Zero Trust → Access → Service Auth → Service Tokens** → create one (e.g.
   `yz-ingest`). Cloudflare gives a **Client ID** (ends in
   `.access`) and a **Client Secret** (shown once).
2. Add a policy on the **Admin API** application that allows this service token.
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
