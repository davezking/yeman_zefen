export type RowResult<T> = { item: T; ok: true } | { item: T; ok: false; message: string };

/**
 * Run `fn` for every item, a few at a time, and report each outcome. It never throws: a failed row is
 * a result, so one bad track cannot hide what happened to the others.
 */
export async function runBulk<T>(
  items: T[],
  fn: (item: T) => Promise<unknown>,
  describeError: (err: unknown) => string,
  concurrency = 4,
): Promise<RowResult<T>[]> {
  const results: RowResult<T>[] = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      const item = items[i]!;
      try {
        await fn(item);
        results[i] = { item, ok: true };
      } catch (err) {
        results[i] = { item, ok: false, message: describeError(err) };
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, worker));
  return results;
}
