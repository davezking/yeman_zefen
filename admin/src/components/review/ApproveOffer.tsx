import { Alert, Button, Group, Text } from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useTrackAction } from "../../api/catalog";
import { usePanelRun } from "./panelRun";

/** Shown when the last open item of a track was just closed: the track may be ready to approve. */
export function ApproveOffer({ trackId, name, onDone }: { trackId: number; name: string; onDone: () => void }) {
  const action = useTrackAction();
  const { error, busy, run } = usePanelRun();

  async function approve() {
    const ok = await run(() => action.mutateAsync({ id: trackId, action: "approve" }));
    if (ok) {
      notifications.show({ color: "green", message: `Approved ${name}` });
      onDone();
    }
  }

  return (
    <Alert color="green" title="Nothing left to review on this track">
      <Group justify="space-between">
        <Text size="sm">{name} has no open review items. Approve it now?</Text>
        <Group gap="xs">
          <Button size="xs" color="green" loading={busy} onClick={() => void approve()}>
            Approve now
          </Button>
          <Button size="xs" variant="default" disabled={busy} onClick={onDone}>
            Not now
          </Button>
        </Group>
      </Group>
      {error && (
        <Text size="sm" c="red" mt="xs">
          Can't approve: {error}
        </Text>
      )}
    </Alert>
  );
}

