// Hooks for the moderation pages: the queue, one player, and the actions (each sends a required note).
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { apiFetch } from "./client";

const queueSessionSchema = z.object({
  id: z.string(),
  userId: z.string(),
  displayName: z.string().nullable(),
  shadowBanned: z.boolean(),
  mode: z.string(),
  difficulty: z.string().nullable(),
  generationId: z.number().nullable(),
  receivedAt: z.number(),
  rounds: z.number(),
  score: z.number(),
  flagReason: z.string().nullable(),
});
export type QueueSession = z.infer<typeof queueSessionSchema>;

const queueAnomalySchema = z.object({
  id: z.number(),
  userId: z.string(),
  displayName: z.string().nullable(),
  shadowBanned: z.boolean(),
  /** `{ days: { "YYYY-MM-DD": { rules, ...metrics } } }`, see lib/moderation.ts. */
  details: z.unknown(),
});
export type QueueAnomaly = z.infer<typeof queueAnomalySchema>;

/** Same shape as an anomaly; `details` is `{ displayName, reports, reporters, ... }`, see lib/moderation.ts. */
const queueNameReportSchema = queueAnomalySchema;
export type QueueNameReport = z.infer<typeof queueNameReportSchema>;

const queueSchema = z.object({
  anomalies: z.array(queueAnomalySchema),
  anomaliesMore: z.boolean(),
  sessions: z.array(queueSessionSchema),
  sessionsMore: z.boolean(),
  nameReports: z.array(queueNameReportSchema),
  nameReportsMore: z.boolean(),
});

const roundSchema = z.object({
  trackId: z.number().nullable(),
  question: z.string().nullable(),
  correct: z.boolean(),
  valid: z.boolean(),
  responseMs: z.number().nullable(),
  hintUsed: z.boolean(),
  points: z.number(),
});
export type Round = z.infer<typeof roundSchema>;

const userSessionSchema = z.object({
  id: z.string(),
  mode: z.string(),
  difficulty: z.string().nullable(),
  generationId: z.number().nullable(),
  receivedAt: z.number(),
  rounds: z.number(),
  score: z.number(),
  offline: z.boolean(),
  flagged: z.boolean(),
  flagReason: z.string().nullable(),
  roundDetails: z.array(roundSchema),
});
export type UserSession = z.infer<typeof userSessionSchema>;

const userDetailSchema = z.object({
  user: z.object({
    id: z.string(),
    displayName: z.string().nullable(),
    isAnonymous: z.boolean(),
    country: z.string().nullable(),
    createdAt: z.number(),
    lastSeenAt: z.number().nullable(),
    shadowBanned: z.boolean(),
    deletedAt: z.number().nullable(),
  }),
  points: z.object({ all: z.number(), week: z.number(), weekPeriod: z.string() }),
  sessions: z.array(userSessionSchema),
  flags: z.array(
    z.object({
      id: z.number(),
      status: z.enum(["open", "resolved", "dismissed"]),
      details: z.unknown(),
      resolvedBy: z.string().nullable(),
      resolvedAt: z.number().nullable(),
    }),
  ),
  log: z.array(
    z.object({
      id: z.number(),
      at: z.number(),
      adminEmail: z.string(),
      action: z.string(),
      sessionId: z.string().nullable(),
      reviewItemId: z.number().nullable(),
      note: z.string(),
    }),
  ),
});
export type UserDetail = z.infer<typeof userDetailSchema>;

export const moderationKeys = {
  all: ["moderation"] as const,
  queue: ["moderation", "queue"] as const,
  user: (id: string) => ["moderation", "user", id] as const,
};

export const useModerationQueue = () => useQuery({ queryKey: moderationKeys.queue, queryFn: () => apiFetch("/admin/moderation/queue", queueSchema) });

export const useModerationUser = (id: string) =>
  useQuery({ queryKey: moderationKeys.user(id), queryFn: () => apiFetch(`/admin/moderation/users/${encodeURIComponent(id)}`, userDetailSchema) });

const anything = z.record(z.string(), z.unknown());

/** An action's mutation: it refreshes the queue and every open player view when it succeeds. */
function useAction<V extends { note: string }>(path: (v: V) => string, body: (v: V) => unknown) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: V) => apiFetch(path(v), anything, { method: "POST", json: body(v) }),
    onSuccess: () => qc.invalidateQueries({ queryKey: moderationKeys.all }),
  });
}

const e = encodeURIComponent;

/** `reviewItemId` also resolves the flag (anomaly or name report) the ban answers. */
export const useShadowBan = () =>
  useAction<{ userId: string; banned: boolean; note: string; reviewItemId?: number }>(
    (v) => `/admin/users/${e(v.userId)}/shadow-ban`,
    ({ banned, note, reviewItemId }) => ({ banned, note, reviewItemId }),
  );
export const useVoidSession = () => useAction<{ sessionId: string; note: string }>((v) => `/admin/sessions/${e(v.sessionId)}/void`, ({ note }) => ({ note }));
export const useDismissSession = () => useAction<{ sessionId: string; note: string }>((v) => `/admin/sessions/${e(v.sessionId)}/dismiss`, ({ note }) => ({ note }));
export const useDismissFlag = () => useAction<{ flagId: number; note: string }>((v) => `/admin/moderation/flags/${v.flagId}/dismiss`, ({ note }) => ({ note }));
