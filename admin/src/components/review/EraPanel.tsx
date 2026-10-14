import { Alert, Button, Group, NumberInput, Select, SimpleGrid, Stack, Text } from "@mantine/core";
import { useState } from "react";
import { useFreshTrack, useGenerations, usePatchTrack } from "../../api/catalog";
import { ApiError } from "../../api/client";
import { useCloseItem, useRefreshQueue } from "../../api/review";
import { eraPatch } from "../../lib/review";
import { TrackCard } from "./TrackCard";
import { usePanelRun } from "./panelRun";
import type { PanelProps } from "./types";

/**
 * A track whose era could not be worked out. A year is enough (the era follows it), or pick an era by hand, which
 * pins it. The server settles the item when the edit makes the era known.
 */
export function EraPanel({ item, onClosed }: PanelProps) {
  const t = item.track;
  const generations = useGenerations();
  const patchTrack = usePatchTrack(t.id, { silent: true });
  const fresh = useFreshTrack();
  const refresh = useRefreshQueue();
  const close = useCloseItem();
  const { error, busy, run } = usePanelRun();

  const [year, setYear] = useState<number | "">(t.releaseYear ?? "");
  const [era, setEra] = useState<string | null>(null);
  const patch = eraPatch({ year, generationId: era }, { year: t.releaseYear, generationId: t.generationId });
  const changed = Object.keys(patch).length > 0;

  async function save() {
    const ok = await run(async () => {
      await patchTrack.mutateAsync(patch);
      refresh();
      // The server closes the item when the era is known afterwards. Ask it, rather than guess.
      const after = await fresh(t.id);
      if (after.openReviewItems.some((i) => i.id === item.id)) {
        throw new ApiError(0, "still_unknown", "The era is still unknown. Enter a year, or pick an era.");
      }
    });
    if (ok) onClosed(item);
  }

  async function dismiss() {
    if (await run(() => close.mutateAsync({ id: item.id, action: "dismiss" }))) onClosed(item);
  }

  return (
    <Stack>
      <Text size="sm" c="dimmed">
        No era could be worked out for this track{t.releaseYear === null ? ": it has no release year" : ""}. A year places
        it in an era; picking an era sets it by hand.
      </Text>
      <SimpleGrid cols={{ base: 1, sm: 2 }}>
        <NumberInput
          label="Release year"
          min={1900}
          max={2100}
          allowDecimal={false}
          allowNegative={false}
          value={year}
          onChange={(v) => setYear(typeof v === "number" ? v : "")}
        />
        <Select
          label="Era"
          placeholder="Follow the year"
          clearable
          data={(generations.data ?? []).map((g) => ({
            value: String(g.id),
            label: `${g.nameEn}${g.yearFrom || g.yearTo ? ` (${g.yearFrom ?? "…"}–${g.yearTo ?? "…"})` : ""}`,
          }))}
          value={era}
          onChange={setEra}
        />
      </SimpleGrid>
      {error && <Alert color="red">{error}</Alert>}
      <Group>
        <Button color="green" loading={busy} disabled={!changed} onClick={() => void save()}>
          Save
        </Button>
        <Button variant="default" disabled={busy} onClick={() => void dismiss()}>
          Leave it unknown
        </Button>
      </Group>
      <TrackCard trackId={t.id} heading="Track" />
    </Stack>
  );
}
