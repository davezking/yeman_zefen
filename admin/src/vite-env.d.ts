/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE?: string;
  /** "firebase" to sign in with Google (src/auth/login.ts); anything else uses Cloudflare Access. */
  readonly VITE_ADMIN_LOGIN?: string;
  /** The Firebase web app's config, needed with VITE_ADMIN_LOGIN=firebase. Public identifiers, not secrets. */
  readonly VITE_FIREBASE_API_KEY?: string;
  readonly VITE_FIREBASE_AUTH_DOMAIN?: string;
  readonly VITE_FIREBASE_PROJECT_ID?: string;
  readonly VITE_FIREBASE_APP_ID?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
