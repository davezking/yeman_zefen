export type Bindings = {
  DB: D1Database;
  /** Per-IP limit on /v1 (Workers Rate Limiting binding). Absent in local dev, where the limit is skipped. */
  IP_LIMITER?: RateLimit;
  CLIPS: R2Bucket;
  SOURCE: R2Bucket;
  ENV: "dev" | "staging" | "prod";
  FIREBASE_PROJECT_ID: string;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  CDN_BASE_URL: string;
  /** Exact origin of the admin SPA (e.g. https://admin.example.com). The only origin allowed CORS on /admin/*. */
  ADMIN_ORIGIN: string;
  /** Cloudflare Access service-token client id allowed on /admin/ingest/*. */
  INGEST_SERVICE_CLIENT_ID: string;
  /** Secret. Fine-grained GitHub PAT, Actions read/write on GH_REPO only, used to dispatch the ingest workflows. */
  GH_DISPATCH_TOKEN?: string;
  /** `owner/name` of the repository that holds the ingest workflows. */
  GH_REPO: string;
  /** Branch (or tag) the dispatched workflows run from. */
  GH_REF: string;
  /** `https://<account>.r2.cloudflarestorage.com`. With the two secrets below, lets the Worker presign reads of `yz-source`. */
  R2_ENDPOINT?: string;
  /** Name of the private source bucket; defaults to `yz-source`. */
  R2_SOURCE_BUCKET?: string;
  /** Secrets. An R2 API token that can read `yz-source`: `wrangler secret put R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`. */
  R2_ACCESS_KEY_ID?: string;
  R2_SECRET_ACCESS_KEY?: string;
  /** Remote config tunables (GET /v1/config). Plain vars in wrangler.toml; see src/lib/remoteConfig.ts. */
  CONFIG_INTERSTITIAL_EVERY_ROUNDS: string;
  CONFIG_REGISTER_PROMPT_AFTER_SESSIONS: string;
  CONFIG_REGISTER_PROMPT_COOLDOWN_DAYS: string;
  CONFIG_MIN_APP_VERSION: string;
  CONFIG_DEFAULT_CLIP_MS: string;
  /** Where people without the app ask for account deletion (GET /account-deletion). Unset: that page answers 503. */
  PRIVACY_CONTACT_EMAIL?: string;
  /** Dev-only: when ENV=dev, lets a request with no Access header act as this admin email. */
  DEV_ADMIN_EMAIL?: string;
};

import type { AdminRole } from "./lib/accessAuth";
import type { PlayerUser } from "./lib/firebaseAuth";

export type Variables = {
  requestId: string;
  admin?: { email: string; role: AdminRole };
  service?: { clientId: string };
  /** Set by requireUser() on authenticated /v1 routes. */
  user?: PlayerUser;
  /** Set by onError() so the request log can name the error. */
  errorCode?: string;
};

export type AppEnv = { Bindings: Bindings; Variables: Variables };
