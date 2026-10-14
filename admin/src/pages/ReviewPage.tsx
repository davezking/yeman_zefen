import { Alert, Badge, Button, Card, Grid, Group, Loader, NavLink, ScrollArea, Stack, Tabs, Text, Title } from "@mantine/core";
import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useFreshTrack, type TrackDetail } from "../api/catalog";
import { useReviewCounts, useReviewList, type ReviewRow } from "../api/review";
import { useWhoami } from "../api/whoami";
import { trackName } from "../components/TrackBits";
import { ApproveOffer } from "../components/review/ApproveOffer";
import { AudioPanel } from "../components/review/AudioPanel";
import { DuplicatePanel } from "../components/review/DuplicatePanel";
import { EraPanel } from "../components/review/EraPanel";
import { TranslitPanel } from "../components/review/TranslitPanel";
import type { PanelProps } from "../components/review/types";
import { isReason, itemAfterClosing, REASON_LABEL, REASONS, type Reason } from "../lib/review";

const PANELS: Record<Reason, (props: PanelProps) => React.JSX.Element> = {
  translit_uncertain: TranslitPanel,
  possible_duplicate: DuplicatePanel,
  era_unknown: EraPanel,
  missing_audio: AudioPanel,
  short_audio: AudioPanel,
};

export function ReviewPage() {
  const [sp, setSp] = useSearchParams();
  const counts = useReviewCounts();
  const whoami = useWhoami();
  const fresh = useFreshTrack();

  // The tab is in the URL. With none, open the first tab that has something in it.
  const param = sp.get("reason");
  const reason: Reason = isReason(param) ? param : (REASONS.find((r) => (counts.data?.[r] ?? 0) > 0) ?? REASONS[0]);

  // Without a tab in the URL, the tab depends on the counts: wait for them rather than fetch a list that may not be shown.
  const tabKnown = isReason(param) || counts.isSuccess || counts.isError;
  // Once chosen, the tab is written into the URL, so counts that change later (an item closed, a scrape) never move
  // the admin to another tab mid-review.
  useEffect(() => {
    if (!isReason(param) && counts.isSuccess) setSp({ reason }, { replace: true });
  }, [param, counts.isSuccess, reason, setSp]);
  const list = useReviewList(reason, { enabled: tabKnown });
  // Items closed in this session are hidden at once, not when the list has been fetched again.
  const [closed, setClosed] = useState<ReadonlySet<number>>(new Set());
  const items = (list.data?.pages.flatMap((p) => p.items) ?? []).filter((i) => !closed.has(i.id));
  // The chosen item belongs to a tab, so a stale choice from another tab is ignored.
  const [choice, setChoice] = useState<{ reason: Reason; id: number } | null>(null);
  const current = items.find((i) => choice?.reason === reason && i.id === choice.id) ?? items[0];
  const [offer, setOffer] = useState<{ trackId: number; name: string } | null>(null);

  // An item was closed: show the next one, and if that was the last open item of its track, offer to approve it.
  // Each close asks the server about its track; only the latest answer may set the offer.
  const offerSeq = useRef(0);
  async function onClosed(closedRow: ReviewRow, closedDetail?: TrackDetail) {
    const seq = ++offerSeq.current;
    const next = itemAfterClosing(items.map((i) => i.id), closedRow.id);
    setClosed((prev) => new Set(prev).add(closedRow.id));
    setChoice(next === undefined ? null : { reason, id: next });
    try {
      const detail = closedDetail ?? (await fresh(closedRow.track.id));
      if (seq !== offerSeq.current) return; // a later close is in charge of the offer now
      const approvable = detail.track.status === "ingested" || detail.track.status === "needs_review";
      setOffer(detail.openReviewItems.length === 0 && approvable ? { trackId: closedRow.track.id, name: trackName(detail.track) } : null);
    } catch {
      if (seq === offerSeq.current) setOffer(null); // the queue just moves on
    }
  }

  const Panel = current ? PANELS[current.reason] : null;

  return (
    <Stack>
      <Title order={2}>Review queue</Title>

      <Tabs value={reason} onChange={(v) => v && setSp({ reason: v }, { replace: true })}>
        <Tabs.List>
          {REASONS.map((r) => (
            <Tabs.Tab
              key={r}
              value={r}
              rightSection={
                <Badge size="sm" variant={(counts.data?.[r] ?? 0) > 0 ? "filled" : "light"} color={(counts.data?.[r] ?? 0) > 0 ? "orange" : "gray"}>
                  {counts.data?.[r] ?? "…"}
                </Badge>
              }
            >
              {REASON_LABEL[r]}
            </Tabs.Tab>
          ))}
        </Tabs.List>
      </Tabs>

      {offer && <ApproveOffer key={offer.trackId} trackId={offer.trackId} name={offer.name} onDone={() => setOffer(null)} />}

      {list.isError && <Alert color="red">Could not load this tab.</Alert>}
      {(list.isPending || !tabKnown) && <Loader size="sm" />}
      {list.isSuccess && items.length === 0 && (
        <Card withBorder>
          <Text c="dimmed">Nothing to review under "{REASON_LABEL[reason]}".</Text>
        </Card>
      )}

      {items.length > 0 && (
        <Grid>
          <Grid.Col span={{ base: 12, md: 3 }}>
            <Text size="xs" c="dimmed" mb="xs">Oldest first</Text>
            <ScrollArea.Autosize mah={640}>
              {items.map((i) => (
                <NavLink
                  key={i.id}
                  active={i.id === current?.id}
                  label={trackName(i.track)}
                  description={i.track.artistNameAm}
                  onClick={() => setChoice({ reason, id: i.id })}
                />
              ))}
              {list.hasNextPage && (
                <Group justify="center" my="xs">
                  <Button size="compact-sm" variant="default" loading={list.isFetchingNextPage} onClick={() => list.fetchNextPage()}>
                    Load more
                  </Button>
                </Group>
              )}
            </ScrollArea.Autosize>
          </Grid.Col>
          <Grid.Col span={{ base: 12, md: 9 }}>
            {current && Panel && (
              <Card withBorder>
                {/* Keyed by the item, so moving to the next one starts from clean state. */}
                <Panel key={current.id} item={current} isAdmin={whoami.data?.role === "admin"} onClosed={(row, detail) => void onClosed(row, detail)} />
              </Card>
            )}
          </Grid.Col>
        </Grid>
      )}
    </Stack>
  );
}
