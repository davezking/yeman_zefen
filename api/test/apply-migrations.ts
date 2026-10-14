import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { installGithubFake } from "./githubFake";

// Runs before each test file. Already-applied migrations are skipped, so this is idempotent.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

// Dispatching a workflow must never reach GitHub from a test (see githubFake.ts).
installGithubFake();
