/** m:ss.s, rounded once on the whole value so 59.96 s reads 1:00.0, not 0:60.0. */
export const mmss = (ms: number) => {
  const tenths = Math.round(ms / 100);
  return `${Math.floor(tenths / 600)}:${((tenths % 600) / 10).toFixed(1).padStart(4, "0")}`;
};
