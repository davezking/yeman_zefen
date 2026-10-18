import { Alert, Anchor, Badge, Button, Group, Loader, Stack, Table, Tabs, Text, Title } from "@mantine/core";
import { useState } from "react";
import { Link } from "react-router-dom";
import { useModerationQueue, type QueueAnomaly, type QueueSession } from "../api/moderation";
import { ModerationActionModal, type PendingAction } from "../components/ModerationActionModal";
import { anomalyDays, anomalyRules, flagLabels, ruleLabel } from "../lib/moderation";

const when = (ms: number) => new Date(ms).toISOString().replace("T", " ").slice(0, 16) + " UTC";
const nameOf = (u: { displayName: string | null; userId: string }) => u.displayName ?? u.userId;

export function ModerationPage() {
  const queue = useModerationQueue();
  const [pending, setPending] = useState<PendingAction | null>(null);
  const data = queue.data;

  return (
    <Stack>
      <Title order={2}>Moderation</Title>
      <Text size="sm" c="dimmed">
        Flags raised by the nightly check, and sessions the server flagged when they were played. Every action needs a note and is logged with your email.
      </Text>
      {queue.isPending && <Loader size="sm" />}
      {queue.isError && <Alert color="red">Could not load the queue: {queue.error.message}</Alert>}

      {data && (
        <Tabs defaultValue="flags">
          <Tabs.List>
            <Tabs.Tab value="flags" rightSection={<Badge variant="light" color={data.anomalies.length ? "red" : "gray"}>{count(data.anomalies.length, data.anomaliesMore)}</Badge>}>
              Anomaly flags
            </Tabs.Tab>
            <Tabs.Tab value="sessions" rightSection={<Badge variant="light" color={data.sessions.length ? "orange" : "gray"}>{count(data.sessions.length, data.sessionsMore)}</Badge>}>
              Flagged sessions
            </Tabs.Tab>
          </Tabs.List>
          <Tabs.Panel value="flags" pt="md">
            <Anomalies rows={data.anomalies} more={data.anomaliesMore} onAct={setPending} />
          </Tabs.Panel>
          <Tabs.Panel value="sessions" pt="md">
            <Sessions rows={data.sessions} more={data.sessionsMore} onAct={setPending} />
          </Tabs.Panel>
        </Tabs>
      )}
      {pending && <ModerationActionModal action={pending} onClose={() => setPending(null)} />}
    </Stack>
  );
}

const count = (n: number, more: boolean) => (more ? `${n}+` : String(n));

function PlayerLink({ userId, name, banned }: { userId: string; name: string; banned: boolean }) {
  return (
    <Group gap="xs" wrap="nowrap">
      <Anchor component={Link} to={`/moderation/users/${encodeURIComponent(userId)}`} size="sm">{name}</Anchor>
      {banned && <Badge color="red" variant="light" size="sm">shadow-banned</Badge>}
    </Group>
  );
}

function Anomalies({ rows, more, onAct }: { rows: QueueAnomaly[]; more: boolean; onAct: (a: PendingAction) => void }) {
  if (rows.length === 0) return <Text c="dimmed">No open anomaly flags.</Text>;
  return (
    <Stack gap="xs">
      <Table verticalSpacing="xs">
        <Table.Thead>
          <Table.Tr><Table.Th>Player</Table.Th><Table.Th>Why</Table.Th><Table.Th>Days</Table.Th><Table.Th /></Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((r) => {
            const name = nameOf(r);
            const days = anomalyDays(r.details);
            return (
              <Table.Tr key={r.id}>
                <Table.Td><PlayerLink userId={r.userId} name={name} banned={r.shadowBanned} /></Table.Td>
                <Table.Td>
                  <Stack gap={2}>{anomalyRules(r.details).map((rule) => <Text key={rule} size="sm">{ruleLabel(rule)}</Text>)}</Stack>
                </Table.Td>
                <Table.Td><Text size="sm">{days.map((d) => d.date).join(", ") || "—"}</Text></Table.Td>
                <Table.Td>
                  <Group gap="xs" justify="flex-end" wrap="nowrap">
                    <Button size="compact-sm" variant="default" component={Link} to={`/moderation/users/${encodeURIComponent(r.userId)}`}>Review</Button>
                    {!r.shadowBanned && (
                      <Button size="compact-sm" color="red" variant="light" onClick={() => onAct({ kind: "ban", userId: r.userId, name, banned: true, reviewItemId: r.id })}>
                        Shadow-ban
                      </Button>
                    )}
                    <Button size="compact-sm" variant="default" onClick={() => onAct({ kind: "dismissFlag", flagId: r.id, name })}>Dismiss</Button>
                  </Group>
                </Table.Td>
              </Table.Tr>
            );
          })}
        </Table.Tbody>
      </Table>
      {more && <Text size="sm" c="dimmed">Showing the oldest {rows.length}. Close some to see the rest.</Text>}
    </Stack>
  );
}

function Sessions({ rows, more, onAct }: { rows: QueueSession[]; more: boolean; onAct: (a: PendingAction) => void }) {
  if (rows.length === 0) return <Text c="dimmed">No flagged sessions to review.</Text>;
  return (
    <Stack gap="xs">
      <Table verticalSpacing="xs">
        <Table.Thead>
          <Table.Tr><Table.Th>Played</Table.Th><Table.Th>Player</Table.Th><Table.Th>Why</Table.Th><Table.Th ta="right">Rounds</Table.Th><Table.Th ta="right">Score</Table.Th><Table.Th /></Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((s) => (
            <Table.Tr key={s.id}>
              <Table.Td><Text size="sm">{when(s.receivedAt)}</Text></Table.Td>
              <Table.Td><PlayerLink userId={s.userId} name={nameOf(s)} banned={s.shadowBanned} /></Table.Td>
              <Table.Td><Text size="sm">{flagLabels(s.flagReason).join(", ")}</Text></Table.Td>
              <Table.Td ta="right">{s.rounds}</Table.Td>
              <Table.Td ta="right">{s.score.toLocaleString("en-US")}</Table.Td>
              <Table.Td>
                <Group gap="xs" justify="flex-end" wrap="nowrap">
                  <Button size="compact-sm" color="red" variant="light" onClick={() => onAct({ kind: "void", sessionId: s.id, score: s.score })}>Void</Button>
                  <Button size="compact-sm" variant="default" onClick={() => onAct({ kind: "dismissSession", sessionId: s.id })}>Dismiss</Button>
                </Group>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
      {more && <Text size="sm" c="dimmed">Showing the newest {rows.length}. Close some to see the rest.</Text>}
    </Stack>
  );
}
