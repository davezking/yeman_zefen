import { Anchor, Badge, Card, Group, Loader, Stack, Text } from "@mantine/core";
import { Link } from "react-router-dom";
import { useGenerations, useTrack } from "../../api/catalog";
import { isHttpUrl, mmss } from "../../lib/format";
import { ClipPlayers } from "../ClipPlayers";
import { eraLabel, StatusBadge, trackName } from "../TrackBits";

/** A track at a glance, with its clips to listen to: the incoming one, or a candidate it may duplicate. */
export function TrackCard({
  trackId,
  heading,
  extra,
}: {
  trackId: number;
  heading: string;
  /** Shown under the title, e.g. how close a candidate is. */
  extra?: React.ReactNode;
}) {
  const track = useTrack(trackId);
  const generations = useGenerations();

  if (track.isPending) {
    return (
      <Card withBorder>
        <Loader size="sm" />
      </Card>
    );
  }
  if (track.isError) {
    return (
      <Card withBorder>
        <Text c="red" size="sm">
          Track {trackId} could not be loaded.
        </Text>
      </Card>
    );
  }
  const { track: t, artist, clips } = track.data;
  return (
    <Card withBorder>
      <Stack gap="xs">
        <Group justify="space-between" wrap="nowrap">
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>
            {heading}
          </Text>
          <StatusBadge status={t.status} />
        </Group>
        <div>
          <Text fw={600}>{trackName(t)}</Text>
          {t.titleAm && t.titleLatin && <Text size="sm" c="dimmed">{t.titleLatin}</Text>}
        </div>
        {extra}
        <Text size="sm">
          {artist ? artist.nameAm : `Artist ${t.artistId}`}
          {artist?.nameLatin && <Text span c="dimmed"> / {artist.nameLatin}</Text>}
        </Text>
        <Group gap="xs">
          <Badge variant="light" color="gray">{t.releaseYear ?? "no year"}</Badge>
          <Badge variant="light" color="gray">{eraLabel(generations.data, t.generationId)}</Badge>
          <Badge variant="light" color="gray">{t.durationMs === null ? "length unknown" : mmss(t.durationMs)}</Badge>
        </Group>
        <ClipPlayers clips={clips} />
        <Group gap="md">
          <Anchor component={Link} to={`/tracks/${t.id}`} size="xs" target="_blank">
            Open in editor
          </Anchor>
          {t.sourceUrl && isHttpUrl(t.sourceUrl) && (
            <Anchor href={t.sourceUrl} target="_blank" rel="noreferrer noopener" size="xs">
              Source
            </Anchor>
          )}
        </Group>
      </Stack>
    </Card>
  );
}
