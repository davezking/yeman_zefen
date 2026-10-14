import { Badge, Group, Stack, Text } from "@mantine/core";
import type { Clip } from "../api/catalog";
import { mmss } from "../lib/format";

/** The intro and middle clips of a track: status, start, and a player for each one that is ready. */
export function ClipPlayers({ clips }: { clips: Clip[] }) {
  return (
    <Stack gap="sm">
      {(["intro", "middle"] as const).map((type) => (
        <ClipRow key={type} type={type} clip={clips.find((c) => c.type === type)} />
      ))}
    </Stack>
  );
}

function ClipRow({ type, clip }: { type: "intro" | "middle"; clip: Clip | undefined }) {
  const name = type === "intro" ? "Intro" : "Middle";
  if (!clip) {
    return (
      <Group>
        <Text fw={500} w={60}>{name}</Text>
        <Badge color="gray" variant="light">not cut yet</Badge>
      </Group>
    );
  }
  const color = clip.status === "ready" ? "green" : clip.status === "failed" ? "red" : "yellow";
  return (
    <Stack gap={4}>
      <Group>
        <Text fw={500} w={60}>{name}</Text>
        <Badge color={color} variant="light">{clip.status === "pending" ? "pending: cut job" : clip.status}</Badge>
        <Text size="xs" c="dimmed">starts at {mmss(clip.startMs)}, {(clip.lengthMs / 1000).toFixed(0)} s</Text>
      </Group>
      {clip.url ? (
        <audio controls preload="none" src={clip.url} style={{ width: "100%" }} />
      ) : (
        <Text size="sm" c="dimmed">No file to play until the clip is ready.</Text>
      )}
    </Stack>
  );
}
