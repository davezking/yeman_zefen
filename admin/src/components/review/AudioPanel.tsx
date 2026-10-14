import { Alert, Anchor, Badge, Button, Group, Stack, Table, Text } from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useState } from "react";
import type { TrackDetail } from "../../api/catalog";
import { useCloseItem, useRetireOrReject, useStartCut } from "../../api/review";
import { isHttpUrl } from "../../lib/format";
import { detailRows } from "../../lib/review";
import { ConfirmModal } from "../ConfirmModal";
import { TrackCard } from "./TrackCard";
import { usePanelRun } from "./panelRun";
import type { PanelProps } from "./types";

// Causes after which another cut cannot help: there is no source audio to cut.
const NO_SOURCE = new Set(["no_mp3_link", "no_source_key"]);

/** A problem with a track's source audio (missing, or too short). Cut again, take the track out, or let it be. */
export function AudioPanel({ item, onClosed }: PanelProps) {
  const t = item.track;
  const startCut = useStartCut();
  const retire = useRetireOrReject();
  const close = useCloseItem();
  const { error, busy, run } = usePanelRun();
  const [confirming, setConfirming] = useState(false);
  // The cut job, once started. A retry after a failed close only closes: it must not start a second job.
  const [cutJob, setCutJob] = useState<number | null>(null);

  const rows = detailRows(item.details);
  const cause = rows.find((r) => r.label === "cause")?.value;
  // Only an approved track can be retired; one that was never approved is rejected instead.
  const takeOut = t.status === "approved" ? "retire" : t.status === "ingested" || t.status === "needs_review" ? "reject" : null;

  const closeAfter = async (action: () => Promise<unknown>, resolution: "resolve" | "dismiss" = "resolve") => {
    const ok = await run(async () => {
      await action();
      await close.mutateAsync({ id: item.id, action: resolution, trackId: t.id });
    });
    if (ok) onClosed(item);
  };

  return (
    <Stack>
      <Group gap="xs">
        <Badge color="orange" variant="light">{item.reason === "missing_audio" ? "Source audio is missing" : "Source audio is too short"}</Badge>
        <Text size="sm" c="dimmed">
          {item.reason === "missing_audio"
            ? "The cutter could not find the track's audio."
            : "The track's audio is shorter than the clips that are cut from it."}
        </Text>
      </Group>

      {rows.length > 0 && (
        <Table withTableBorder>
          <Table.Tbody>
            {rows.map((r) => (
              <Table.Tr key={r.label}>
                <Table.Td w={140}><Text size="sm" c="dimmed">{r.label}</Text></Table.Td>
                <Table.Td><Text size="sm" ff="monospace">{r.value}</Text></Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}
      {cause && NO_SOURCE.has(cause) && (
        <Alert color="yellow">
          There is no source audio on record for this track, so cutting again would flag it again. Take it out, or re-run
          the scrape to find the audio.
        </Alert>
      )}

      {error && <Alert color="red">{error}</Alert>}
      <Group>
        <Button
          loading={busy}
          onClick={() =>
            void closeAfter(async () => {
              if (cutJob !== null) return;
              const job = await startCut.mutateAsync(t.id);
              setCutJob(job.id);
              notifications.show({ color: "green", message: `Cut job ${job.id} started. If the audio is still a problem, it will be flagged again.` });
            })
          }
        >
          {cutJob === null ? "Re-run cut" : `Cut job ${cutJob} started: close this item`}
        </Button>
        {takeOut && (
          <Button color="red" variant="light" disabled={busy} onClick={() => setConfirming(true)}>
            {takeOut === "retire" ? "Retire track" : "Reject track"}
          </Button>
        )}
        <Button variant="default" disabled={busy} onClick={() => void closeAfter(async () => undefined, "dismiss")}>
          The audio is fine: dismiss
        </Button>
      </Group>
      {takeOut === "reject" && (
        <Text size="xs" c="dimmed">
          This track was never approved, so taking it out means rejecting it.
        </Text>
      )}
      {t.sourceUrl && isHttpUrl(t.sourceUrl) && (
        <Anchor href={t.sourceUrl} target="_blank" rel="noreferrer noopener" size="sm">
          Open the source page
        </Anchor>
      )}

      <TrackCard trackId={t.id} heading="Track" />

      <ConfirmModal
        opened={confirming}
        title={takeOut === "retire" ? "Retire this track?" : "Reject this track?"}
        confirmLabel={takeOut === "retire" ? "Retire" : "Reject"}
        onClose={() => setConfirming(false)}
        // One request: taking a track out closes all its open items on the server, this one included.
        onConfirm={() =>
          takeOut &&
          void (async () => {
            let after: TrackDetail | undefined;
            if (await run(async () => (after = await retire.mutateAsync({ id: t.id, action: takeOut })))) onClosed(item, after);
          })()
        }
      >
        {takeOut === "retire"
          ? "It leaves the game and cannot be approved again."
          : "A rejected track cannot be approved again."}
      </ConfirmModal>
    </Stack>
  );
}
