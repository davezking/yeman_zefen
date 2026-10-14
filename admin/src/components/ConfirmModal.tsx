import { Button, Group, Modal, Stack, Text } from "@mantine/core";
import type { ReactNode } from "react";

/** A yes/no question before something that cannot be undone. */
export function ConfirmModal({
  opened,
  title,
  children,
  confirmLabel,
  onConfirm,
  onClose,
  color = "red",
}: {
  opened: boolean;
  title: string;
  children: ReactNode;
  confirmLabel: string;
  onConfirm: () => void;
  onClose: () => void;
  color?: string;
}) {
  return (
    <Modal opened={opened} onClose={onClose} title={title}>
      <Stack>
        <Text size="sm">{children}</Text>
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Cancel
          </Button>
          <Button
            color={color}
            onClick={() => {
              onClose();
              onConfirm();
            }}
          >
            {confirmLabel}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
