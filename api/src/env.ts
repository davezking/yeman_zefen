export type Bindings = {
  DB: D1Database;
  CLIPS: R2Bucket;
  SOURCE: R2Bucket;
  ENV: "dev" | "prod";
  FIREBASE_PROJECT_ID: string;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  CDN_BASE_URL: string;
};

export type Variables = {
  requestId: string;
};

export type AppEnv = { Bindings: Bindings; Variables: Variables };
