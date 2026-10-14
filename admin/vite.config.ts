import react from "@vitejs/plugin-react";
import { defineConfig, loadEnv } from "vite";

// Dev server on 5173 is the origin the Worker allows through ADMIN_ORIGIN (api/wrangler.toml).
export default defineConfig(({ command, mode }) => {
  // A production build without VITE_API_BASE would call localhost from the deployed site, so fail the build instead.
  // loadEnv reads .env files and VITE_* variables from the environment (Pages sets them there).
  if (command === "build" && !loadEnv(mode, ".").VITE_API_BASE) {
    throw new Error("VITE_API_BASE must be set for a production build (e.g. https://api.example.com).");
  }
  return {
    plugins: [react()],
    server: { port: 5173, strictPort: true },
  };
});
