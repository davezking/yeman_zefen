/** True when a D1/Drizzle error is a UNIQUE constraint violation (Drizzle wraps it; the SQLite text is on `cause`). */
export function isUniqueViolation(err: unknown): boolean {
  const e = err as { message?: string; cause?: { message?: string } };
  return /UNIQUE constraint failed/i.test(`${e?.message ?? ""} ${e?.cause?.message ?? ""}`);
}
