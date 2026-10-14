// Local stand-in for the public CDN in front of the `yz-clips` bucket, so the admin UI can play clips under
// `wrangler dev` (CDN_BASE_URL points here). Dev only: in prod the CDN domain serves the bucket directly.
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { ApiError } from "../lib/errors";

// Clip keys look like clips/{trackId}/{type}-v{version}.mp3: plain path segments, nothing that could climb out.
const clipKey = z.string().regex(/^clips\/(?:[\w-]+\/)*[\w.-]+$/).refine((k) => !k.split("/").includes(".."));

const notFound = () => new ApiError(404, "not_found", "Route not found");

export const devCdn = new Hono<AppEnv>();

devCdn.get("/*", async (c) => {
  if (c.env.ENV !== "dev") throw notFound();
  let raw: string;
  try {
    // c.req.path is already decoded; decode the raw pathname exactly once instead.
    raw = decodeURIComponent(new URL(c.req.url).pathname.replace(/^\/cdn\//, ""));
  } catch {
    throw notFound(); // a malformed %-escape is just a key that does not exist
  }
  const parsed = clipKey.safeParse(raw);
  if (!parsed.success) throw notFound();
  const key = parsed.data;

  const head = await c.env.CLIPS.head(key);
  if (!head) throw new ApiError(404, "not_found", "Clip not found");

  // Audio elements ask for byte ranges to seek. One `bytes=` range is supported; anything else gets the whole file.
  const range = parseRange(c.req.header("range"), head.size);
  if (range === "unsatisfiable") {
    return new Response(null, { status: 416, headers: { "content-range": `bytes */${head.size}` } });
  }
  const object = await c.env.CLIPS.get(key, range ? { range } : undefined);
  if (!object) throw new ApiError(404, "not_found", "Clip not found");

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("accept-ranges", "bytes");
  if (range) {
    headers.set("content-range", `bytes ${range.offset}-${range.offset + range.length - 1}/${head.size}`);
    headers.set("content-length", String(range.length));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set("content-length", String(head.size));
  return new Response(object.body, { headers });
});

/** A single `bytes=a-b`, `bytes=a-` or `bytes=-n` range, clamped to the file. Malformed or multiple ranges are ignored. */
export function parseRange(header: string | undefined, size: number): { offset: number; length: number } | "unsatisfiable" | undefined {
  const m = header ? /^bytes=(\d*)-(\d*)$/.exec(header.trim()) : null;
  if (!m || (m[1] === "" && m[2] === "")) return undefined;
  if (m[1] === "") {
    const suffix = Number(m[2]);
    if (suffix === 0 || size === 0) return "unsatisfiable";
    const length = Math.min(suffix, size);
    return { offset: size - length, length };
  }
  const offset = Number(m[1]);
  if (m[2] !== "" && Number(m[2]) < offset) return undefined; // last < first is invalid: ignore it (RFC 9110 14.1.1)
  if (offset >= size) return "unsatisfiable";
  const end = m[2] === "" ? size - 1 : Math.min(Number(m[2]), size - 1);
  return { offset, length: end - offset + 1 };
}
