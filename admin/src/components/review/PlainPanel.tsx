import { Alert, Button, Code, Group, Stack, Text } from "@mantine/core";
import { useCloseItem } from "../../api/review";
import { TrackCard } from "./TrackCard";
import { usePanelRun } from "./panelRun";
import type { PanelProps } from "./types";

/** For an item whose details are not what its reason leads us to expect: show what there is, and let it be closed. */
export function PlainPanel({ item, onClosed }: PanelProps) {
  const close = useCloseItem();
  const { error, busy, run } = usePanelRun();
  const closeWith = async (action: "resolve" | "dismiss") => {
    if (await run(() => close.mutateAsync({ id: item.id, action, trackId: item.track.id }))) onClosed(item);
  };
  return (
    <Stack>
      <Alert color="yellow" title="Unexpected details">
        <Text size="sm">This item's details are not in the shape this flag normally has, so there is nothing to edit here.</Text>
        {item.details !== null && item.details !== undefined && <Code block mt="xs">{JSON.stringify(item.details, null, 2)}</Code>}
      </Alert>
      <TrackCard trackId={item.track.id} heading="Track" />
      {error && <Alert color="red">{error}</Alert>}
      <Group>
        <Button color="green" loading={busy} onClick={() => void closeWith("resolve")}>
          Resolve
        </Button>
        <Button variant="default" disabled={busy} onClick={() => void closeWith("dismiss")}>
          Dismiss
        </Button>
      </Group>
    </Stack>
  );
}
