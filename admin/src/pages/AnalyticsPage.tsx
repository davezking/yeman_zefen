import { BarChart, LineChart } from "@mantine/charts";
import { Alert, Anchor, Badge, Button, Card, Group, Loader, SimpleGrid, Stack, Table, Text, TextInput, Title } from "@mantine/core";
import { useState } from "react";
import { useAnalytics } from "../api/analytics";
import { TARGETS, axisLabel, kpis, lastDays, percent, retentionByWeek, type Kpi } from "../lib/analytics";
import { missingDaysText, rangeError, type DayRange } from "../lib/reports";

const number = (n: number) => n.toLocaleString("en-US");
const STATUS_COLOR = { met: "green", missed: "red", unknown: "gray" } as const;
const STATUS_TEXT = { met: "Target met", missed: "Below target", unknown: "No data yet" } as const;

export function AnalyticsPage() {
  const [range, setRange] = useState<DayRange>(() => lastDays(Date.now(), 30));
  const error = rangeError(range.from, range.to);
  const query = useAnalytics(error === null ? range : null);
  const data = query.data;
  const pending = data?.days.filter((d) => !d.rolledUp).map((d) => d.date) ?? [];

  return (
    <Stack>
      <Title order={2}>Analytics</Title>
      <Text size="sm" c="dimmed">
        From the nightly roll-up. Days are UTC. “Installs” are not in our data, so new users (first session recorded) stand in for them.
      </Text>

      <Group align="flex-end">
        <TextInput label="From" type="date" value={range.from} onChange={(e) => setRange({ ...range, from: e.currentTarget.value })} />
        <TextInput label="To" type="date" value={range.to} onChange={(e) => setRange({ ...range, to: e.currentTarget.value })} />
        {[7, 30, 90].map((n) => (
          <Button key={n} variant="default" onClick={() => setRange(lastDays(Date.now(), n))}>Last {n} days</Button>
        ))}
      </Group>

      {error && <Text c="red" size="sm">{error}</Text>}
      {query.isPending && error === null && <Loader size="sm" />}
      {query.isError && <Alert color="red">Could not load analytics: {query.error.message}</Alert>}
      {pending.length > 0 && (
        <Alert color="yellow" title="Some days are not rolled up">
          {missingDaysText(pending)} {pending.length === 1 ? "has" : "have"} no roll-up yet (today, yesterday before 00:30 UTC, or a failed run), so
          {pending.length === 1 ? " it is" : " they are"} left out of the figures and shown as gaps.
        </Alert>
      )}

      {data && <Dashboard data={data} />}

      <Card withBorder>
        <Text fw={600} mb="xs">Official install and revenue figures</Text>
        <Group>
          <Anchor href="https://play.google.com/console" target="_blank" rel="noreferrer">Play Console</Anchor>
          <Anchor href="https://appstoreconnect.apple.com" target="_blank" rel="noreferrer">App Store Connect</Anchor>
          <Anchor href="https://admob.google.com" target="_blank" rel="noreferrer">AdMob</Anchor>
        </Group>
      </Card>
    </Stack>
  );
}

function Dashboard({ data }: { data: NonNullable<ReturnType<typeof useAnalytics>["data"]> }) {
  const days = data.days;
  const label = (date: string) => axisLabel(date, data);
  // A day without a roll-up is a gap (null), not a zero.
  const dauSeries = days.map((d) => ({ date: label(d.date), DAU: d.rolledUp ? d.dau : null, "New users": d.rolledUp ? d.newUsers : null }));
  const rpsSeries = days.map((d) => ({ date: label(d.date), "Rounds per session": d.rolledUp && d.sessions > 0 ? d.roundsPerSession : null }));
  const adSeries = days.map((d) => ({
    date: label(d.date),
    "Interstitials shown": d.rolledUp ? d.interstitialsShown : null,
    "Rewarded completed": d.rolledUp ? d.rewardedCompleted : null,
  }));
  const weeks = retentionByWeek(days);
  const adTotals = days.reduce(
    (t, d) => ({ shown: t.shown + d.interstitialsShown, rewarded: t.rewarded + d.rewardedCompleted }),
    { shown: 0, rewarded: 0 },
  );
  const totalPlays = data.countries.placed + data.countries.unknown;

  return (
    <>
      <SimpleGrid cols={{ base: 1, sm: 2, lg: 5 }}>
        {kpis(days).map((k) => (
          <KpiCard key={k.key} kpi={k} />
        ))}
      </SimpleGrid>

      <Card withBorder>
        <Text fw={600} mb="xs">Daily active users and new users</Text>
        <LineChart
          h={260}
          data={dauSeries}
          dataKey="date"
          connectNulls={false}
          series={[
            { name: "DAU", color: "blue.6" },
            { name: "New users", color: "teal.6" },
          ]}
          referenceLines={[{ y: TARGETS.dau, label: `DAU target ${number(TARGETS.dau)}`, color: "red.5" }]}
          withLegend
        />
      </Card>

      <Card withBorder>
        <Text fw={600} mb="xs">Rounds per session</Text>
        <LineChart
          h={220}
          data={rpsSeries}
          dataKey="date"
          connectNulls={false}
          series={[{ name: "Rounds per session", color: "violet.6" }]}
          referenceLines={[{ y: TARGETS.roundsPerSession, label: `Target ${TARGETS.roundsPerSession}`, color: "red.5" }]}
          withLegend
        />
      </Card>

      <Card withBorder>
        <Text fw={600} mb="xs">Retention by cohort week</Text>
        <Text size="xs" c="dimmed" mb="xs">
          Users created that week who played 1, 7 and 30 days later. A dash means no cohort day of the week has the answer yet. Targets: D1 {percent(TARGETS.d1, 0)}, D7 {percent(TARGETS.d7, 0)}, D30 {percent(TARGETS.d30, 0)}.
        </Text>
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Week of</Table.Th>
              <Table.Th ta="right">New users</Table.Th>
              <Table.Th ta="right">D1</Table.Th>
              <Table.Th ta="right">D7</Table.Th>
              <Table.Th ta="right">D30</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {weeks.map((w) => (
              <Table.Tr key={w.week}>
                <Table.Td>
                  {w.week}
                  {w.days < 7 && <Text span size="xs" c="dimmed"> ({w.days} of 7 days in range)</Text>}
                </Table.Td>
                <Table.Td ta="right">{number(w.newUsers)}</Table.Td>
                <Table.Td ta="right" c={cellColor(w.d1, TARGETS.d1)}>{percent(w.d1)}</Table.Td>
                <Table.Td ta="right" c={cellColor(w.d7, TARGETS.d7)}>{percent(w.d7)}</Table.Td>
                <Table.Td ta="right" c={cellColor(w.d30, TARGETS.d30)}>{percent(w.d30)}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Card>

      <SimpleGrid cols={{ base: 1, md: 2 }}>
        <Card withBorder>
          <Group justify="space-between" mb="xs">
            <Text fw={600}>Top countries (plays)</Text>
            <Badge variant="light" size="lg">
              Diaspora share {data.countries.diasporaShare === null ? "–" : percent(data.countries.diasporaShare)}
            </Badge>
          </Group>
          {data.countries.top.length === 0 ? (
            <Text c="dimmed">No plays in this range.</Text>
          ) : (
            <BarChart h={260} data={data.countries.top} dataKey="country" series={[{ name: "plays", color: "blue.6" }]} orientation="vertical" />
          )}
          <Text size="xs" c="dimmed" mt="xs">
            Diaspora share is plays outside ET over plays in a known country. {number(data.countries.unknown)} of {number(totalPlays)} plays had no country and are left out.
          </Text>
        </Card>

        <Card withBorder>
          <Text fw={600} mb="xs">Ads</Text>
          <Text size="sm" mb="xs">
            {number(adTotals.shown)} interstitials shown · {number(adTotals.rewarded)} rewarded completions
          </Text>
          <LineChart
            h={220}
            data={adSeries}
            dataKey="date"
            connectNulls={false}
            series={[
              { name: "Interstitials shown", color: "orange.6" },
              { name: "Rewarded completed", color: "grape.6" },
            ]}
            withLegend
          />
        </Card>
      </SimpleGrid>
    </>
  );
}

const cellColor = (v: number | null, target: number) => (v === null ? "dimmed" : v >= target ? "green" : "red");

function KpiCard({ kpi }: { kpi: Kpi }) {
  const show = (v: number) => (kpi.percent ? percent(v) : Number.isInteger(v) ? number(v) : v.toFixed(1));
  return (
    <Card withBorder>
      <Text size="sm" c="dimmed">{kpi.label}</Text>
      <Text fz={28} fw={700}>{kpi.value === null ? "–" : show(kpi.value)}</Text>
      <Text size="xs" c="dimmed">Target {kpi.percent ? percent(kpi.target, 0) : number(kpi.target)}</Text>
      <Badge mt={6} color={STATUS_COLOR[kpi.status]} variant="light">{STATUS_TEXT[kpi.status]}</Badge>
      <Text size="xs" c="dimmed" mt={6}>{kpi.basis}</Text>
    </Card>
  );
}
