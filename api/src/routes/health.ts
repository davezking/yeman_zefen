import { Hono } from "hono";
import type { AppEnv } from "../env";

export const health = new Hono<AppEnv>().get("/", (c) => c.json({ ok: true, env: c.env.ENV }));
