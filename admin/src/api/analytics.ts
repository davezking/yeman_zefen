import { useQuery } from "@tanstack/react-query";
import { z } from "zod";
import type { DayRange } from "../lib/reports";
import { apiFetch } from "./client";

const count = z.number().nullable();

const dayStats = z.object({
  date: z.string(),
  /** False for a day with no roll-up yet; its zeros are not real. */
  rolledUp: z.boolean(),
  dau: z.number(),
  /** Users created that day: the stand-in for installs, which the data does not have. */
  newUsers: z.number(),
  sessions: z.number(),
  rounds: z.number(),
  roundsPerSession: z.number(),
  /** Of that day's new users, how many played 1, 7 and 30 days later; null until that day is rolled up. */
  retained: z.object({ d1: count, d7: count, d30: count }),
  interstitialsShown: z.number(),
  rewardedCompleted: z.number(),
});
export type DayStats = z.infer<typeof dayStats>;

const analyticsSchema = z.object({
  from: z.string(),
  to: z.string(),
  days: z.array(dayStats),
  countries: z.object({
    placed: z.number(),
    unknown: z.number(),
    diasporaShare: z.number().nullable(),
    top: z.array(z.object({ country: z.string(), plays: z.number() })),
  }),
});
export type Analytics = z.infer<typeof analyticsSchema>;

/** The analytics for a range; nothing is fetched while `range` is null (an incomplete or invalid range). */
export const useAnalytics = (range: DayRange | null) =>
  useQuery({
    queryKey: ["analytics", range?.from, range?.to],
    enabled: range !== null,
    queryFn: () => apiFetch(`/admin/analytics?${new URLSearchParams({ from: range!.from, to: range!.to })}`, analyticsSchema),
  });
