import { Hono } from "hono";
import { runScheduled } from "./cron/rollups";
import type { AppEnv, Bindings } from "./env";
import { adminCors } from "./lib/cors";
import { onError, onNotFound } from "./lib/errors";
import { requestId } from "./lib/requestId";
import { requestLog } from "./lib/requestLog";
import { accountDeletion } from "./routes/accountDeletion";
import { admin } from "./routes/admin";
import { devCdn } from "./routes/devCdn";
import { health } from "./routes/health";
import { v1 } from "./routes/v1";

const app = new Hono<AppEnv>();

app.use("*", requestId());
app.use("*", requestLog());
app.onError(onError);
app.notFound(onNotFound);

app.route("/health", health);
app.route("/account-deletion", accountDeletion);
app.route("/cdn", devCdn);
app.route("/v1", v1);
// CORS runs before the admin routers so preflight OPTIONS requests are answered without auth.
app.use("/admin/*", adminCors());
app.route("/admin", admin);

// fetch serves the API; scheduled is the Cron Trigger (wrangler.toml `crons`).
export default {
  fetch: app.fetch,
  // Awaited (not waitUntil) so that a failed day makes the invocation fail in Cloudflare.
  scheduled: async (controller: ScheduledController, env: Bindings) => {
    await runScheduled(env, controller.scheduledTime);
  },
};
