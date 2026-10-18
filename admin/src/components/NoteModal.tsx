import { Button, Group, Modal, Stack, Text, Textarea } from "@mantine/core";
import { useState, type ReactNode } from "react";
import { NOTE_MAX, noteProblem } from "../lib/moderation";

/**
 * Asks for the note every moderation action must carry; Confirm stays off until there is one.
 * Render it only while an action is pending, so each action starts with an empty note.
 */
export function NoteModal({
  opened,
  title,
  children,
  confirmLabel,
  color = "red",
  loading = false,
  onConfirm,
  onClose,
}: {
  opened: boolean;
  title: string;
  children: ReactNode;
  confirmLabel: string;
  color?: string;
  loading?: boolean;
  onConfirm: (note: string) => void;
  onClose: () => void;
}) {
  const [note, setNote] = useState("");
  const [touched, setTouched] = useState(false);
  const problem = noteProblem(note);
  return (
    <Modal opened={opened} onClose={onClose} title={title}>
      <Stack>
        <Text size="sm">{children}</Text>
        <Textarea
          label="Note"
          description="Why you are doing this. It is kept in the moderation log with your email."
          required
          autosize
          minRows={3}
          maxLength={NOTE_MAX}
          value={note}
          onChange={(e) => setNote(e.currentTarget.value)}
          onBlur={() => setTouched(true)}
          error={touched ? problem : null}
          data-autofocus
        />
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button
            color={color}
            loading={loading}
            disabled={problem !== null}
            onClick={() => onConfirm(note.trim())}
          >
            {confirmLabel}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
