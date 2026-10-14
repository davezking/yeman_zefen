import { Alert, Anchor, Badge, Button, Code, Group, Loader, Modal, NumberInput, Stack, Table, Text, TextInput, Title } from "@mantine/core";
import { useEffect, useState } from "react";
import { useJobs, useStartJob, type JobRow } from "../api/jobs";
import { duration, errorList, isActive, paramsText, summaryText } from "../lib/jobs";

const COLOR = { queued: "gray", running: "blue", succeeded: "green", failed: "red" } as const;
const SINCE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function JobsPage() {
  const jobs = useJobs();
  const start = useStartJob();
  const [dialog, setDialog] = useState(false);
  const [limit, setLimit] = useState<number | string>("");
  const [since, setSince] = useState("");
  // Running jobs show a live duration.
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  const sinceOk = since === "" || SINCE_RE.test(since);

  return (
    <Stack>
      <Group justify="space-between">
        <Title order={2}>Jobs</Title>
        <Group>
          <Button variant="default" loading={start.isPending && start.variables?.kind === "cut"} onClick={() => start.mutate({ kind: "cut", params: { allMissing: true } })}>
            Cut missing clips
          </Button>
          <Button onClick={() => { start.reset(); setDialog(true); }}>Run scraper</Button>
        </Group>
      </Group>

      <Text size="sm" c="dimmed">
        The scraper also runs every Monday at 03:17 UTC. To change that, edit the <Code>cron</Code> line in{" "}
        <Code>.github/workflows/ingest-scrape.yml</Code>.
      </Text>

      {start.isError && !dialog && <Alert color="red" title="Could not start the job">{start.error.message}</Alert>}
      {start.isSuccess && !dialog && <Alert color="green">Job {start.data.job.id} started.</Alert>}
      {jobs.isPending && <Loader size="sm" />}
      {jobs.isError && <Alert color="red">Could not load jobs: {jobs.error.message}</Alert>}
      {jobs.data?.length === 0 && <Text c="dimmed">No jobs yet.</Text>}
      {jobs.data && jobs.data.length > 0 && (
        <Table withTableBorder verticalSpacing="xs">
          <Table.Thead>
            <Table.Tr><Table.Th>#</Table.Th><Table.Th>Kind</Table.Th><Table.Th>Status</Table.Th><Table.Th>Params</Table.Th><Table.Th>Started</Table.Th><Table.Th>Duration</Table.Th><Table.Th>Summary</Table.Th><Table.Th>Run</Table.Th></Table.Tr>
          </Table.Thead>
          <Table.Tbody>{jobs.data.map((j) => <JobRowView key={j.id} job={j} now={now} />)}</Table.Tbody>
        </Table>
      )}

      <Modal opened={dialog} onClose={() => setDialog(false)} title="Run scraper">
        <Stack>
          <NumberInput label="Limit" description="Most posts to scrape. Empty: no limit." min={1} max={10000} allowDecimal={false} value={limit} onChange={setLimit} />
          <TextInput label="Since" description="Only posts from this date on (YYYY-MM-DD)." placeholder="2026-01-31" value={since} onChange={(e) => setSince(e.currentTarget.value)} error={sinceOk ? undefined : "Use YYYY-MM-DD"} />
          {start.isError && <Alert color="red">{start.error.message}</Alert>}
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setDialog(false)}>Cancel</Button>
            <Button
              disabled={!sinceOk}
              loading={start.isPending}
              onClick={() =>
                start.mutate(
                  { kind: "scrape", params: { ...(typeof limit === "number" ? { limit } : {}), ...(since ? { since } : {}) } },
                  { onSuccess: () => { setDialog(false); setLimit(""); setSince(""); } },
                )
              }
            >
              Start
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}

function JobRowView({ job, now }: { job: JobRow; now: number }) {
  const errors = job.status === "failed" ? errorList(job.summary) : [];
  return (
    <Table.Tr>
      <Table.Td>{job.id}</Table.Td>
      <Table.Td>{job.kind}</Table.Td>
      <Table.Td><Badge color={COLOR[job.status]} variant="light">{job.status}{isActive(job.status) && " …"}</Badge></Table.Td>
      <Table.Td><Text size="xs" ff="monospace">{paramsText(job.params)}</Text></Table.Td>
      <Table.Td>{job.startedAt ? new Date(job.startedAt).toLocaleString() : "–"}</Table.Td>
      <Table.Td>{duration(job.startedAt, job.finishedAt, now)}</Table.Td>
      <Table.Td>
        <Text size="sm" c={job.status === "failed" ? "red" : undefined}>{summaryText(job.summary)}</Text>
        {errors.length > 0 && (
          <Text size="xs" c="dimmed" style={{ maxHeight: 80, overflowY: "auto" }}>{errors.join(" · ")}</Text>
        )}
      </Table.Td>
      <Table.Td>{job.ghRunUrl && /^https?:\/\//.test(job.ghRunUrl) ? <Anchor href={job.ghRunUrl} target="_blank" rel="noreferrer noopener" size="sm">GitHub</Anchor> : "–"}</Table.Td>
    </Table.Tr>
  );
}
