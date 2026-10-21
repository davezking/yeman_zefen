// How the admin signs in. Must match the Worker's ADMIN_LOGIN (api/wrangler.toml, docs/ops.md):
//   - "access" (the default): Cloudflare Access in front of the site and the API sets a cookie that
//     every request carries. Needs both on hostnames of one domain.
//   - "firebase": the admin signs in with Google here, and every request carries the Firebase ID token
//     as `Authorization: Bearer`. No cookie, so it works on the free pages.dev and workers.dev addresses.
export type AdminLogin = "access" | "firebase";

/** Anything but "firebase" is "access", like the Worker. */
export function adminLoginFrom(env: { VITE_ADMIN_LOGIN?: string }): AdminLogin {
  return env.VITE_ADMIN_LOGIN === "firebase" ? "firebase" : "access";
}

export const adminLogin = (): AdminLogin => adminLoginFrom(import.meta.env);
