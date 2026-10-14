import { Hono } from "hono";
import type { AppEnv } from "./env";
import { adminCors } from "./lib/cors";
import { onError, onNotFound } from "./lib/errors";
import { requestId } from "./lib/requestId";
import { admin } from "./routes/admin";
import { devCdn } from "./routes/devCdn";
import { health } from "./routes/health";
import { v1 } from "./routes/v1";

const app = new Hono<AppEnv>();

app.use("*", requestId());
app.onError(onError);
app.notFound(onNotFound);

app.route("/health", health);
app.route("/cdn", devCdn);
app.route("/v1", v1);
// CORS runs before the admin routers so preflight OPTIONS requests are answered without auth.
app.use("/admin/*", adminCors());
app.route("/admin", admin);

export default app;
