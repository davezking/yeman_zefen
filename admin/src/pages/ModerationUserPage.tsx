import { BarChart } from "@mantine/charts";
import { Alert, Anchor, Badge, Button, Card, Group, Loader, SimpleGrid, Stack, Table, Text, Title } from "@mantine/core";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useModerationUser, type UserDetail, type UserSession } from "../api/moderation";
import { ModerationActionModal, type PendingAction } from "../components/ModerationActionModal";
import { anomalyDays, anomalyRules, flagLabels, median, responseHistogram, ruleLabel } from "../lib/moderation";

const when = (ms: number | null) => (ms === null ? "—" : new Date(ms).toISOString().replace("T", " ").slice(0, 16) + " UTC");
const number = (n: number) => n.toLocaleString("en-US");
const ACTION_TEXT: Record<string, string> = {
  shadow_ban: "Shadow-banned",
  shadow_unban: "Ban lifted",
  void_session: "Voided a session",
  dismiss_session: "Dismissed a session",
  dismiss_flag: "Dismissed a flag",
};

export function ModerationUserPage() {
  const { id = "" } = useParams();
  const query = useModerationUser(id);
  const [pending, setPending] = useState<PendingAction | null>(null);

  return (
    <Stack>
      <Anchor component={Link} to="/moderation" size="sm">← Moderation queue</Anchor>
      {query.isPending && <Loader size="sm" />}
      {query.isError && <Alert color="red">Could not load this player: {query.error.message}</Alert>}
      {query.data && <Player data={query.data} onAct={setPending} />}
      {pending && <ModerationActionModal action={pending} onClose={() => setPending(null)} />}
    </Stack>
  );
}

function Player({ data, onAct }: { data: UserDetail; onAct: (a: PendingAction) => void }) {
  const { user, points } = data;
  const name = user.displayName ?? user.id;
  const rounds = data.sessions.flatMap((s) => s.roundDetails);
  const answered = rounds.map((r) => r.responseMs).filter((ms): ms is number => ms !== null);
  const openFlag = data.flags.find((f) => f.status === "open");
  const mid = median(answered);

  return (
    <>
      <Group justify="space-between">
        <Group>
          <Title order={2}>{name}</Title>
          {user.shadowBanned && <Badge color="red">shadow-banned</Badge>}
          {user.isAnonymous && <Badge color="gray" variant="light">guest</Badge>}
          {user.deletedAt !== null && <Badge color="gray">deleted</Badge>}
        </Group>
        <Button
          color={user.shadowBanned ? "blue" : "red"}
          variant={user.shadowBanned ? "default" : "filled"}
          onClick={() => onAct({ kind: "ban", userId: user.id, name, banned: !user.shadowBanned, reviewItemId: user.shadowBanned ? undefined : openFlag?.id })}
        >
          {user.shadowBanned ? "Lift shadow-ban" : "Shadow-ban"}
        </Button>
      </Group>

      <SimpleGrid cols={{ base: 2, sm: 4 }}>
        <Stat label="Points, all time" value={number(points.all)} />
        <Stat label={`Points, ${points.weekPeriod}`} value={number(points.week)} />
        <Stat label="Country" value={user.country ?? "—"} />
        <Stat label="Last seen" value={when(user.lastSeenAt)} />
      </SimpleGrid>
      <Text size="xs" c="dimmed">Player id {user.id} · joined {when(user.createdAt)}</Text>

      <Card withBorder>
        <Group justify="space-between" mb="xs">
          <Text fw={600}>Response times</Text>
          <Text size="sm" c="dimmed">
            {answered.length} answered rounds in the last {data.sessions.length} sessions{mid !== null && ` · median ${number(Math.round(mid))} ms`}
          </Text>
        </Group>
        {answered.length === 0 ? (
          <Text c="dimmed">No answered rounds to chart.</Text>
        ) : (
          <BarChart h={220} data={responseHistogram(answered)} dataKey="label" series={[{ name: "count", color: "blue.6" }]} xAxisProps={{ interval: 1, tick: { fontSize: 11 } }} />
        )}
        <Text size="xs" c="dimmed" mt="xs">A person's answers spread out; a script's pile into one or two bars, usually the fastest ones.</Text>
      </Card>

      <Card withBorder>
        <Text fw={600} mb="xs">Anomaly flags</Text>
        {data.flags.length === 0 ? <Text c="dimmed">None.</Text> : (
          <Stack gap="sm">
            {data.flags.map((f) => (
              <Group key={f.id} align="flex-start" justify="space-between">
                <Stack gap={2}>
                  <Group gap="xs">
                    <Badge color={f.status === "open" ? "red" : "gray"} variant="light">{f.status}</Badge>
                    {anomalyRules(f.details).map((r) => <Text key={r} size="sm">{ruleLabel(r)}</Text>)}
                  </Group>
                  {anomalyDays(f.details).map((d) => (
                    <Text key={d.date} size="xs" c="dimmed">{d.date}: {metricsText(d.metrics)}</Text>
                  ))}
                  {f.resolvedBy && <Text size="xs" c="dimmed">Closed by {f.resolvedBy} · {when(f.resolvedAt)}</Text>}
                </Stack>
                {f.status === "open" && (
                  <Button size="compact-sm" variant="default" onClick={() => onAct({ kind: "dismissFlag", flagId: f.id, name })}>Dismiss</Button>
                )}
              </Group>
            ))}
          </Stack>
        )}
      </Card>

      <Card withBorder>
        <Text fw={600} mb="xs">Recent sessions</Text>
        {data.sessions.length === 0 ? <Text c="dimmed">No sessions.</Text> : (
          <Stack gap="md">{data.sessions.map((s) => <SessionBlock key={s.id} session={s} onAct={onAct} />)}</Stack>
        )}
      </Card>

      <Card withBorder>
        <Text fw={600} mb="xs">Moderation log</Text>
        {data.log.length === 0 ? <Text c="dimmed">Nothing logged for this player.</Text> : (
          <Table verticalSpacing="xs">
            <Table.Thead><Table.Tr><Table.Th>When</Table.Th><Table.Th>Admin</Table.Th><Table.Th>Action</Table.Th><Table.Th>Note</Table.Th></Table.Tr></Table.Thead>
            <Table.Tbody>
              {data.log.map((l) => (
                <Table.Tr key={l.id}>
                  <Table.Td><Text size="sm">{when(l.at)}</Text></Table.Td>
                  <Table.Td><Text size="sm">{l.adminEmail}</Text></Table.Td>
                  <Table.Td><Text size="sm">{ACTION_TEXT[l.action] ?? l.action}{l.sessionId && ` (${l.sessionId.slice(0, 8)})`}</Text></Table.Td>
                  <Table.Td><Text size="sm">{l.note}</Text></Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </Card>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <Card withBorder padding="sm">
      <Text size="xs" c="dimmed">{label}</Text>
      <Text fw={600}>{value}</Text>
    </Card>
  );
}

function metricsText(metrics: Record<string, unknown>): string {
  return Object.entries(metrics)
    .filter(([k, v]) => k !== "rules" && v !== null)
    .map(([k, v]) => `${k} ${String(v)}`)
    .join(" · ");
}

function SessionBlock({ session: s, onAct }: { session: UserSession; onAct: (a: PendingAction) => void }) {
  const [open, setOpen] = useState(false);
  const voided = s.flagReason?.split(",").includes("voided") ?? false;
  return (
    <Stack gap="xs">
      <Group justify="space-between">
        <Group gap="xs">
          <Text size="sm" fw={500}>{when(s.receivedAt)}</Text>
          <Text size="sm" c="dimmed">{s.mode}{s.difficulty && ` · ${s.difficulty}`} · {s.rounds} rounds · {number(s.score)} points{s.offline && " · offline"}</Text>
          {s.flagged && <Badge color={voided ? "gray" : "orange"} variant="light">{flagLabels(s.flagReason).join(", ")}</Badge>}
        </Group>
        <Group gap="xs">
          <Button size="compact-sm" variant="subtle" onClick={() => setOpen(!open)}>{open ? "Hide rounds" : "Rounds"}</Button>
          {!voided && <Button size="compact-sm" color="red" variant="light" onClick={() => onAct({ kind: "void", sessionId: s.id, score: s.score })}>Void</Button>}
          {s.flagged && !voided && <Button size="compact-sm" variant="default" onClick={() => onAct({ kind: "dismissSession", sessionId: s.id })}>Dismiss</Button>}
        </Group>
      </Group>
      {open && (
        <Table verticalSpacing={2} fz="sm">
          <Table.Thead>
            <Table.Tr><Table.Th>#</Table.Th><Table.Th>Question</Table.Th><Table.Th>Result</Table.Th><Table.Th ta="right">Response</Table.Th><Table.Th ta="right">Points</Table.Th></Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {s.roundDetails.map((r, i) => (
              <Table.Tr key={i}>
                <Table.Td>{i + 1}</Table.Td>
                <Table.Td>{r.question ?? "—"}{r.hintUsed && " (hint)"}</Table.Td>
                <Table.Td>{!r.valid ? "invalid" : r.correct ? "correct" : "wrong"}</Table.Td>
                <Table.Td ta="right">{r.responseMs === null ? "—" : `${number(r.responseMs)} ms`}</Table.Td>
                <Table.Td ta="right">{r.points}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}
    </Stack>
  );
}
