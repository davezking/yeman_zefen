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
