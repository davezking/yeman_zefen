import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            ACCESS_TEAM_DOMAIN: "https://yz.cloudflareaccess.com",
            ACCESS_AUD: "test-access-aud",
            INGEST_SERVICE_CLIENT_ID: "test-service.client",
            GH_DISPATCH_TOKEN: "test-gh-token", // a dummy; the GitHub calls are faked (test/githubFake.ts)
          },
        },
      }),
    ],
    test: { setupFiles: ["./test/apply-migrations.ts"] },
  };
});
