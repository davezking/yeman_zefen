/**
 * The caller's country as Cloudflare places it (`request.cf.country`), or null. Never taken from
 * the client. Cloudflare reports "XX" when it cannot place the IP and "T1" for Tor; neither is a
 * country, so they read as null and must not overwrite a stored one.
 */
export function requestCountry(req: Request): string | null {
  const raw = (req.cf as { country?: unknown } | undefined)?.country;
  return typeof raw === "string" && /^[A-Z]{2}$/.test(raw) && raw !== "XX" && raw !== "T1" ? raw : null;
}
