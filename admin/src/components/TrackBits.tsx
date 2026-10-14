import { Badge, Group, Tooltip } from "@mantine/core";
import type { ClipStatus, Generation, TrackStatus } from "../api/catalog";

const STATUS_COLOR: Record<TrackStatus, string> = {
  ingested: "gray",
  needs_review: "yellow",
  approved: "green",
  rejected: "red",
  retired: "dark",
};

export const statusLabel = (s: TrackStatus) => s.replace("_", " ");

export function StatusBadge({ status }: { status: TrackStatus }) {
  return (
    <Badge color={STATUS_COLOR[status]} variant="light">
      {statusLabel(status)}
    </Badge>
  );
}

const DOT_COLOR: Record<ClipStatus | "missing", string> = {
  ready: "var(--mantine-color-green-6)",
  pending: "var(--mantine-color-yellow-6)",
  failed: "var(--mantine-color-red-6)",
  missing: "var(--mantine-color-gray-4)",
};

function Dot({ label, status }: { label: string; status: ClipStatus | null }) {
  const state = status ?? "missing";
  return (
    <Tooltip label={`${label}: ${status ?? "not cut yet"}`}>
      <span
        role="img"
        aria-label={`${label} clip ${status ?? "not cut yet"}`}
        style={{ width: 10, height: 10, borderRadius: "50%", background: DOT_COLOR[state], display: "inline-block" }}
      />
    </Tooltip>
  );
}

/** Two dots: the intro clip, then the middle clip. */
export function ClipDots({ intro, middle }: { intro: ClipStatus | null; middle: ClipStatus | null }) {
  return (
    <Group gap={6} wrap="nowrap">
      <Dot label="Intro" status={intro} />
      <Dot label="Middle" status={middle} />
    </Group>
  );
}

export function eraLabel(generations: Generation[] | undefined, id: number | null): string {
  if (id === null) return "—";
  return generations?.find((g) => g.id === id)?.nameEn ?? `#${id}`;
}

/** What to call a track in lists and messages: its Fidel title, else the Latin one, else its id. */
export const trackName = (t: { id: number; titleAm: string | null; titleLatin: string | null }) =>
  t.titleAm ?? t.titleLatin ?? `Track ${t.id}`;
