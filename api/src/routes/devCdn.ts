// Local stand-in for the public CDN in front of the `yz-clips` bucket, so the admin UI can play clips under
// `wrangler dev` (CDN_BASE_URL points here). Dev only: in prod the CDN domain serves the bucket directly.
import { Hono } from "hono";
import type { AppEnv } from "../env";
import { ApiError } from "../lib/errors";

export const devCdn = new Hono<AppEnv>();

devCdn.get("/*", async (c) => {
  const key = decodeURIComponent(c.req.path.replace(/^\/cdn\//, ""));
  if (c.env.ENV !== "dev" || !key.startsWith("clips/") || key.includes("..")) {
    throw new ApiError(404, "not_found", "Route not found");
  }
  // Audio elements ask for byte ranges to seek, so pass the Range header through to R2.
  const object = await c.env.CLIPS.get(key, { range: c.req.raw.headers });
  if (!object) throw new ApiError(404, "not_found", "Clip not found");

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("accept-ranges", "bytes");
  const range = c.req.header("range") ? object.range : undefined;
  if (range) {
    // The runtime may include keys with undefined values, so test the values rather than `in`.
    const r = range as { offset?: number; length?: number; suffix?: number };
    const offset = r.suffix !== undefined ? object.size - Math.min(r.suffix, object.size) : (r.offset ?? 0);
    const length = r.suffix !== undefined ? Math.min(r.suffix, object.size) : (r.length ?? object.size - offset);
    headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("content-length", String(length));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set("content-length", String(object.size));
  return new Response(object.body, { headers });
});
