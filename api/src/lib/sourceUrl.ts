// Presigned reads of the private `yz-source` bucket through R2's S3 endpoint, so the admin's browser can load a
// track's full audio without the bucket ever being public.
import { AwsClient } from "aws4fetch";
import type { Bindings } from "../env";
import { ApiError } from "./errors";

export const SOURCE_URL_TTL_SECONDS = 600;

/** A GET URL for `key` that stops working after SOURCE_URL_TTL_SECONDS. 503 if the R2 credentials are not set. */
export async function presignSourceUrl(env: Bindings, key: string, now = Date.now()): Promise<string> {
  const { R2_ENDPOINT: endpoint, R2_ACCESS_KEY_ID: accessKeyId, R2_SECRET_ACCESS_KEY: secretAccessKey } = env;
  if (!endpoint || !accessKeyId || !secretAccessKey) {
    throw new ApiError(503, "source_signing_unconfigured", "R2 credentials are not configured on the Worker");
  }
  const bucket = env.R2_SOURCE_BUCKET || "yz-source";
  const base = `${endpoint.replace(/\/+$/, "")}/${bucket}/${key.split("/").map(encodeURIComponent).join("/")}`;
  const url = new URL(base);
  url.searchParams.set("X-Amz-Expires", String(SOURCE_URL_TTL_SECONDS));
  const aws = new AwsClient({ accessKeyId, secretAccessKey, service: "s3", region: "auto" });
  const signed = await aws.sign(new Request(url, { method: "GET" }), {
    aws: { signQuery: true, datetime: new Date(now).toISOString().replace(/[:-]|\.\d{3}/g, "") },
  });
  return signed.url;
}
