import { Hono } from "hono";
import type { AppEnv } from "./env";
import { onError, onNotFound } from "./lib/errors";
import { requestId } from "./lib/requestId";
import { admin } from "./routes/admin";
import { health } from "./routes/health";

const app = new Hono<AppEnv>();

app.use("*", requestId());
app.onError(onError);
app.notFound(onNotFound);

app.route("/health", health);
app.route("/admin", admin);

export default app;
