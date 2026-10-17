import { useQuery } from "@tanstack/react-query";
import { z } from "zod";
import { reportFilename, type DayRange } from "../lib/reports";
import { apiFetch, apiFetchBlob } from "./client";

const rowSchema = z.object({
  trackId: z.number(),
  titleAm: z.string().nullable(),
  titleLatin: z.string().nullable(),
  artistAm: z.string(),
  artistLatin: z.string().nullable(),
  album: z.string().nullable(),
  releaseYear: z.number().nullable(),
  plays: z.number(),
});
export type RoyaltyRow = z.infer<typeof rowSchema>;

const reportSchema = z.object({
  from: z.string(),
  to: z.string(),
  includesToday: z.boolean(),
  totalPlays: z.number(),
  rows: z.array(rowSchema),
});
export type RoyaltyReport = z.infer<typeof reportSchema>;

const query = (r: DayRange, format: "json" | "csv") => `?${new URLSearchParams({ from: r.from, to: r.to, format })}`;

/** The report for a range; nothing is fetched while `range` is null (an incomplete or invalid range). */
export const useRoyaltyReport = (range: DayRange | null) =>
  useQuery({
    queryKey: ["royalty-report", range?.from, range?.to],
    enabled: range !== null,
    queryFn: () => apiFetch(`/admin/reports/royalty${query(range!, "json")}`, reportSchema),
  });

/** Fetches the CSV (with the Access cookie, which a plain link would not carry) and saves it. */
export async function downloadRoyaltyCsv(range: DayRange): Promise<void> {
  const blob = await apiFetchBlob(`/admin/reports/royalty${query(range, "csv")}`);
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = reportFilename(range);
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}
