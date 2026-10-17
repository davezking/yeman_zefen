import { Alert, Button, Group, Loader, Stack, Table, Text, TextInput, Title } from "@mantine/core";
import { useState } from "react";
import { downloadRoyaltyCsv, useRoyaltyReport } from "../api/reports";
import { useWhoami } from "../api/whoami";
import { lastMonth, lastQuarter, missingDaysText, rangeError, type DayRange } from "../lib/reports";

/** Rows shown in the preview. The total and the CSV always cover every track. */
const PREVIEW_ROWS = 200;
const number = (n: number) => n.toLocaleString("en-US");

export function ReportsPage() {
  const whoami = useWhoami();
  // The Worker refuses the editor role; say so here instead of showing a failed request.
  if (whoami.data && whoami.data.role !== "admin") {
    return (
      <Stack>
        <Title order={2}>Royalty report</Title>
        <Text c="dimmed">The royalty report is for admins.</Text>
      </Stack>
    );
  }
  return <Report />;
}

function Report() {
  const [range, setRange] = useState<DayRange>(() => lastMonth(Date.now()));
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const error = rangeError(range.from, range.to);
  const report = useRoyaltyReport(error === null ? range : null);
  // The Worker says which days are not rolled up: today, yesterday before 00:30 UTC, or a failed run.
  const missing = report.data?.missingDays ?? [];

  async function download(partial: boolean) {
    setSaving(true);
    setSaveError(null);
    try {
      await downloadRoyaltyCsv(range, partial);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "The download failed.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Stack>
      <Title order={2}>Royalty report</Title>
      <Text size="sm" c="dimmed">
        Plays per track for the music association, from the nightly roll-up. Days are UTC.
      </Text>

      <Group align="flex-end">
        <TextInput label="From" type="date" value={range.from} onChange={(e) => setRange({ ...range, from: e.currentTarget.value })} />
        <TextInput label="To" type="date" value={range.to} onChange={(e) => setRange({ ...range, to: e.currentTarget.value })} />
        <Button variant="default" onClick={() => setRange(lastMonth(Date.now()))}>Last month</Button>
        <Button variant="default" onClick={() => setRange(lastQuarter(Date.now()))}>Last quarter</Button>
        <Button disabled={error !== null || !report.data} loading={saving} onClick={() => void download(missing.length > 0)}>Download CSV</Button>
      </Group>

      {error && <Text c="red" size="sm">{error}</Text>}
      {missing.length > 0 && (
        <Alert color="yellow" title="This report is not final">
          {report.data?.includesToday ? "Today is not counted yet: " : ""}
          Plays are missing for {missingDaysText(missing)}, which {missing.length === 1 ? "has" : "have"} not been rolled up. The roll-up runs at 00:30 UTC for the day
          before; a day that stays missing means its run failed. The CSV is named <code>-partial</code> until the range is complete.
        </Alert>
      )}
      {saveError && <Alert color="red" title="Could not download the CSV">{saveError}</Alert>}
      {report.isPending && error === null && <Loader size="sm" />}
      {report.isError && <Alert color="red">Could not load the report: {report.error.message}</Alert>}

      {report.data && (
        <>
          <Text fw={600}>
            {number(report.data.totalPlays)} plays across {number(report.data.rows.length)} tracks
          </Text>
          {report.data.rows.length === 0 ? (
            <Text c="dimmed">No plays in this range.</Text>
          ) : (
            <Table withTableBorder verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Title</Table.Th>
                  <Table.Th>Artist</Table.Th>
                  <Table.Th>Album</Table.Th>
                  <Table.Th>Year</Table.Th>
                  <Table.Th ta="right">Plays</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {report.data.rows.slice(0, PREVIEW_ROWS).map((r) => (
                  <Table.Tr key={r.trackId}>
                    <Table.Td>{[r.titleAm, r.titleLatin].filter(Boolean).join(" · ") || "(untitled)"}</Table.Td>
                    <Table.Td>{[r.artistAm, r.artistLatin].filter(Boolean).join(" · ")}</Table.Td>
                    <Table.Td>{r.album ?? ""}</Table.Td>
                    <Table.Td>{r.releaseYear ?? ""}</Table.Td>
                    <Table.Td ta="right">{number(r.plays)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
              <Table.Tfoot>
                <Table.Tr>
                  <Table.Th colSpan={4}>Total</Table.Th>
                  <Table.Th ta="right">{number(report.data.totalPlays)}</Table.Th>
                </Table.Tr>
              </Table.Tfoot>
            </Table>
          )}
          {report.data.rows.length > PREVIEW_ROWS && (
            <Text size="sm" c="dimmed">Showing the {PREVIEW_ROWS} most played of {number(report.data.rows.length)} tracks. The CSV has them all.</Text>
          )}
        </>
      )}
    </Stack>
  );
}
