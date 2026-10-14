import { Alert, Badge, Button, Card, Group, Loader, SimpleGrid, Stack, Text, Tooltip } from "@mantine/core";
import { useState } from "react";
import { trackName } from "../TrackBits";
import { useArtistDetail, useCloseItem, useMarkDuplicate, useMergeArtist } from "../../api/review";
import { parseDuplicate, type Candidate, type DuplicateDetails } from "../../lib/review";
import { ConfirmModal } from "../ConfirmModal";
import { PlainPanel } from "./PlainPanel";
import { TrackCard } from "./TrackCard";
import { usePanelRun } from "./panelRun";
import type { PanelProps } from "./types";

type Props = PanelProps & { details: DuplicateDetails };

/** A track or artist that looks like one already in the catalog. Which one it is decides the choices. */
export function DuplicatePanel(props: PanelProps) {
  const details = parseDuplicate(props.item.details);
  if (!details) return <PlainPanel {...props} />;
  return details.field === "artist" ? <ArtistDuplicates {...props} details={details} /> : <TrackDuplicates {...props} details={details} />;
}

const percent = (n: number | undefined) => (n === undefined ? null : `${Math.round(n * 100)}% match`);

function CandidateNotInCatalog({ candidate }: { candidate: Candidate }) {
  return (
    <Card withBorder>
      <Text size="sm" fw={500}>Not in the catalog yet</Text>
      <Text size="xs" c="dimmed" style={{ wordBreak: "break-all" }}>{candidate.sourceUrl ?? "no source"}</Text>
      <Text size="xs" c="dimmed" mt="xs">
        It was scraped in the same batch, so it has no id to link to. Open this item again after the run has finished.
      </Text>
    </Card>
  );
}

// ------------------------------------------------------------------ the same song?

function TrackDuplicates({ item, details, onClosed }: Props) {
  const t = item.track;
  const mark = useMarkDuplicate();
  const close = useCloseItem();
  const { error, busy, run } = usePanelRun();
  const [confirming, setConfirming] = useState<number | null>(null);

  const markAs = async (canonicalId: number) => {
    // The server settles this item in the same step as the rejection.
    if (await run(() => mark.mutateAsync({ trackId: t.id, canonicalTrackId: canonicalId }))) onClosed(item);
  };
  const different = async () => {
    if (await run(() => close.mutateAsync({ id: item.id, action: "dismiss" }))) onClosed(item);
  };

  return (
    <Stack>
      <Group gap="xs">
        <Badge color="orange" variant="light">Possible duplicate song</Badge>
        {details.variant_of && <Badge color="grape" variant="light">looks like a variant: {details.variant_of}</Badge>}
        <Text size="sm" c="dimmed">Listen to both, then say whether they are the same song.</Text>
      </Group>

      <TrackCard trackId={t.id} heading="Incoming" />

      <SimpleGrid cols={{ base: 1, md: 2 }}>
        {details.candidates.map((c, i) =>
          c.id === undefined ? (
            <CandidateNotInCatalog key={c.sourceUrl ?? i} candidate={c} />
          ) : (
            <Stack key={c.id} gap="xs">
              <TrackCard
                trackId={c.id}
                heading="Already in the catalog"
                extra={
                  <Group gap="xs">
                    {c.score !== undefined && <Badge variant="light">{percent(c.score)}</Badge>}
                    {c.durationDiff !== undefined && (
                      <Badge variant="light" color="yellow">length differs by {Math.round(c.durationDiff * 100)}%</Badge>
                    )}
                  </Group>
                }
              />
              <Button color="red" variant="light" disabled={busy} onClick={() => setConfirming(c.id!)}>
                Same song → mark this as a duplicate of #{c.id}
              </Button>
            </Stack>
          ),
        )}
      </SimpleGrid>

      {error && <Alert color="red">{error}</Alert>}
      <Group>
        <Button variant="default" loading={busy} onClick={() => void different()}>
          Different songs: dismiss
        </Button>
      </Group>

      <ConfirmModal
        opened={confirming !== null}
        title="Mark as a duplicate?"
        confirmLabel="Mark as duplicate"
        onClose={() => setConfirming(null)}
        onConfirm={() => confirming !== null && void markAs(confirming)}
      >
        {trackName(t)} will be rejected and linked to track #{confirming}. Nothing is deleted, but a rejected track cannot
        be approved again.
      </ConfirmModal>
    </Stack>
  );
}

// ------------------------------------------------------------------ the same artist?

function ArtistDuplicates({ item, details, isAdmin, onClosed }: Props) {
  const t = item.track;
  // Once this artist has been merged away it is gone, so it must not be looked up again.
  const [merged, setMerged] = useState(false);
  const current = useArtistDetail(merged ? undefined : t.artistId);
  const merge = useMergeArtist();
  const close = useCloseItem();
  const { error, busy, run } = usePanelRun();
  const [confirming, setConfirming] = useState<number | null>(null);
  const target = useArtistDetail(confirming ?? undefined);

  const closeWith = async (action: "resolve" | "dismiss") => {
    if (await run(() => close.mutateAsync({ id: item.id, action }))) onClosed(item);
  };
  const mergeInto = async (intoId: number) => {
    const ok = await run(async () => {
      // A retry after a failed close only closes: the artist was already merged away.
      if (!merged) {
        await merge.mutateAsync({ fromId: t.artistId, intoId });
        setMerged(true);
      }
      await close.mutateAsync({ id: item.id, action: "resolve" });
    });
    if (ok) onClosed(item);
  };

  const ours = current.data?.artist;
  return (
    <Stack>
      <Group gap="xs">
        <Badge color="orange" variant="light">Possible duplicate artist</Badge>
        <Text size="sm" c="dimmed">
          The artist of this track looks like one that is already in the catalog.
        </Text>
      </Group>

      <Card withBorder>
        <Text size="xs" c="dimmed" tt="uppercase" fw={700}>This track's artist</Text>
        <Text fw={600}>
          {t.artistNameAm}
          {t.artistNameLatin && <Text span c="dimmed"> / {t.artistNameLatin}</Text>}
        </Text>
        {current.isPending ? <Loader size="xs" /> : current.data && <ArtistFacts detail={current.data} />}
        <Text size="sm" mt="xs">Track: {trackName(t)}</Text>
      </Card>

      <SimpleGrid cols={{ base: 1, md: 2 }}>
        {details.candidates.map((c, i) =>
          c.id === undefined ? (
            <CandidateNotInCatalog key={c.sourceUrl ?? i} candidate={c} />
          ) : (
            <ArtistCandidate
              key={c.id}
              candidate={c}
              isAdmin={isAdmin}
              busy={busy}
              alreadyThisArtist={c.id === t.artistId}
              onMerge={() => setConfirming(c.id!)}
              onResolve={() => void closeWith("resolve")}
            />
          ),
        )}
      </SimpleGrid>

      {error && <Alert color="red">{error}</Alert>}
      <Group>
        <Button variant="default" loading={busy} onClick={() => void closeWith("dismiss")}>
          Different artists: dismiss
        </Button>
      </Group>

      <ConfirmModal
        opened={confirming !== null}
        title="Merge these artists?"
        confirmLabel="Merge"
        onClose={() => setConfirming(null)}
        onConfirm={() => confirming !== null && void mergeInto(confirming)}
      >
        {ours?.nameAm ?? t.artistNameAm} ({current.data?.trackCount ?? "?"} track{current.data?.trackCount === 1 ? "" : "s"}) will
        be merged into {target.data?.artist.nameAm ?? `artist #${confirming}`}. Its tracks and aliases move over, and its
        name becomes an alias of the other artist. This cannot be undone.
      </ConfirmModal>
    </Stack>
  );
}

function ArtistFacts({ detail }: { detail: NonNullable<ReturnType<typeof useArtistDetail>["data"]> }) {
  const aliases = detail.aliases.map((a) => a.alias);
  return (
    <Text size="xs" c="dimmed">
      {detail.trackCount} track{detail.trackCount === 1 ? "" : "s"}
      {aliases.length > 0 && ` · also written ${aliases.slice(0, 5).join(", ")}${aliases.length > 5 ? ", …" : ""}`}
    </Text>
  );
}

function ArtistCandidate({
  candidate,
  isAdmin,
  busy,
  alreadyThisArtist,
  onMerge,
  onResolve,
}: {
  candidate: Candidate;
  isAdmin: boolean;
  busy: boolean;
  alreadyThisArtist: boolean;
  onMerge: () => void;
  onResolve: () => void;
}) {
  const detail = useArtistDetail(candidate.id);
  return (
    <Card withBorder>
      <Stack gap="xs">
        <Group justify="space-between" wrap="nowrap">
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>Already in the catalog</Text>
          {candidate.score !== undefined && <Badge variant="light">{percent(candidate.score)}</Badge>}
        </Group>
        {detail.isPending && <Loader size="xs" />}
        {detail.isError && <Text c="red" size="sm">Artist {candidate.id} could not be loaded.</Text>}
        {detail.data && (
          <>
            <Text fw={600}>
              {detail.data.artist.nameAm}
              {detail.data.artist.nameLatin && <Text span c="dimmed"> / {detail.data.artist.nameLatin}</Text>}
            </Text>
            <ArtistFacts detail={detail.data} />
          </>
        )}
        {alreadyThisArtist ? (
          <>
            <Text size="sm">This is already the track's artist: the two were merged.</Text>
            <Button color="green" variant="light" disabled={busy} onClick={onResolve}>
              Mark resolved
            </Button>
          </>
        ) : (
          <Tooltip label="Only admins can merge artists" disabled={isAdmin}>
            <span>
              <Button color="red" variant="light" fullWidth disabled={busy || !isAdmin || detail.isError} onClick={onMerge}>
                Same artist → merge into this one
              </Button>
            </span>
          </Tooltip>
        )}
      </Stack>
    </Card>
  );
}
