import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// Dev server on 5173 is the origin the Worker allows through ADMIN_ORIGIN (api/wrangler.toml).
export default defineConfig({
  plugins: [react()],
  server: { port: 5173, strictPort: true },
});
