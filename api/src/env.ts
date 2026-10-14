export type Bindings = {
  DB: D1Database;
  CLIPS: R2Bucket;
  SOURCE: R2Bucket;
  ENV: "dev" | "prod";
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
  /** Dev-only: when ENV=dev, lets a request with no Access header act as this admin email. */
  DEV_ADMIN_EMAIL?: string;
};

import type { AdminRole } from "./lib/accessAuth";

export type Variables = {
  requestId: string;
  admin?: { email: string; role: AdminRole };
  service?: { clientId: string };
};

export type AppEnv = { Bindings: Bindings; Variables: Variables };
