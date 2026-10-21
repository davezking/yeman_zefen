import react from "@vitejs/plugin-react";
import { defineConfig, loadEnv } from "vite";

// Dev server on 5173 is the origin the Worker allows through ADMIN_ORIGIN (api/wrangler.toml).
export default defineConfig(({ command, mode }) => {
  // A production build without VITE_API_BASE would call localhost from the deployed site, so fail the build instead.
  // loadEnv reads .env files and VITE_* variables from the environment (Pages sets them there).
  const env = loadEnv(mode, ".");
  if (command === "build" && !env.VITE_API_BASE) {
    throw new Error("VITE_API_BASE must be set for a production build (e.g. https://api.example.com).");
  }
  // Signing in with Google needs the Firebase web app's config; without it the site could not sign anyone in.
  if (command === "build" && env.VITE_ADMIN_LOGIN === "firebase") {
    const missing = ["VITE_FIREBASE_API_KEY", "VITE_FIREBASE_AUTH_DOMAIN", "VITE_FIREBASE_PROJECT_ID"].filter((k) => !env[k]);
    if (missing.length > 0) throw new Error(`VITE_ADMIN_LOGIN=firebase needs ${missing.join(", ")} (docs/ops.md, "Admin authentication").`);
  }
  return {
    plugins: [react()],
    server: { port: 5173, strictPort: true },
  };
});
