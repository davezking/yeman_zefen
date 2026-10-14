import {
  Alert,
  Badge,
  Button,
  Checkbox,
  Group,
  Loader,
  Modal,
  Select,
  Stack,
  Table,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { useDebouncedValue } from "@mantine/hooks";
import { useEffect, useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  TRACK_STATUSES,
  useGenerations,
  useGenres,
  useTrackAction,
  useTrackList,
  type TrackAction,
  type TrackFilters,
  type TrackRow,
  type TrackStatus,
} from "../api/catalog";
import { ApiError } from "../api/client";
import { ClipDots, eraLabel, StatusBadge, statusLabel, trackName } from "../components/TrackBits";
import { runBulk, type RowResult } from "../lib/bulk";
import { filtersFromParams, paramsFromFilters } from "../lib/trackFilters";

const describe = (err: unknown) => (err instanceof ApiError ? err.message : "Request failed");

export function TracksPage() {
  const [sp, setSp] = useSearchParams();
  const navigate = useNavigate();
  const filters = filtersFromParams(sp);
  const generations = useGenerations();
  const genres = useGenres();
  const list = useTrackList(filters);
  const action = useTrackAction();

  const [search, setSearch] = useState(filters.q ?? "");
  const [debounced] = useDebouncedValue(search, 300);
  useEffect(() => {
    if ((debounced.trim() || undefined) !== filters.q) setSp(paramsFromFilters({ ...filters, q: debounced.trim() || undefined }), { replace: true });
    // Only the debounced text should trigger this, not the filters it reads.
  }, [debounced]);

  const rows = useMemo(() => list.data?.pages.flatMap((p) => p.items) ?? [], [list.data]);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  // Drop selections that are no longer in the list (a filter change, or rows that left it after an action).
  useEffect(() => {
    setSelected((prev) => {
      const ids = new Set(rows.map((r) => r.id));
      const kept = new Set([...prev].filter((id) => ids.has(id)));
      return kept.size === prev.size ? prev : kept;
    });
  }, [rows]);

  const setFilter = (patch: Partial<TrackFilters>) => setSp(paramsFromFilters({ ...filters, ...patch }), { replace: true });
  const allSelected = rows.length > 0 && rows.every((r) => selected.has(r.id));
  const toggle = (id: number) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (!next.delete(id)) next.add(id);
      return next;
    });

  const [confirmReject, setConfirmReject] = useState(false);
  const [bulkResults, setBulkResults] = useState<{ action: TrackAction; results: RowResult<TrackRow>[] } | null>(null);
  const [running, setRunning] = useState<TrackAction | null>(null);

  async function runBulkAction(kind: TrackAction) {
    const targets = rows.filter((r) => selected.has(r.id));
    setRunning(kind);
    const results = await runBulk(targets, (t) => action.mutateAsync({ id: t.id, action: kind }), describe);
    setRunning(null);
    setBulkResults({ action: kind, results });
    // Rows that went through are done; failed ones stay selected so they can be looked at.
    setSelected(new Set(results.filter((r) => !r.ok).map((r) => r.item.id)));
  }

  const open = (id: number) => navigate({ pathname: `/tracks/${id}`, search: sp.toString() });

  return (
    <Stack>
      <Title order={2}>Tracks</Title>

      <Group align="flex-end">
        <Select
          label="Status"
          placeholder="Any"
          clearable
          data={TRACK_STATUSES.map((s) => ({ value: s, label: statusLabel(s) }))}
          value={filters.status ?? null}
          onChange={(v) => setFilter({ status: (v as TrackStatus | null) ?? undefined })}
        />
        <Select
          label="Era"
          placeholder="Any"
          clearable
          data={(generations.data ?? []).map((g) => ({ value: String(g.id), label: g.nameEn }))}
          value={filters.generationId ? String(filters.generationId) : null}
          onChange={(v) => setFilter({ generationId: v ? Number(v) : undefined })}
        />
        <Select
          label="Genre"
          placeholder="Any"
          clearable
          data={(genres.data ?? []).map((g) => ({ value: String(g.id), label: g.nameEn }))}
          value={filters.genreId ? String(filters.genreId) : null}
          onChange={(v) => setFilter({ genreId: v ? Number(v) : undefined })}
        />
        <TextInput
          label="Search"
          placeholder="Title in Fidel or Latin"
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          style={{ flex: 1, minWidth: 200 }}
        />
      </Group>

      {selected.size > 0 && (
        <Group>
          <Text size="sm">{selected.size} selected</Text>
          <Button size="xs" color="green" loading={running === "approve"} disabled={running !== null} onClick={() => runBulkAction("approve")}>
            Approve selected
          </Button>
          <Button size="xs" color="red" variant="light" disabled={running !== null} onClick={() => setConfirmReject(true)}>
            Reject selected
          </Button>
          <Button size="xs" variant="subtle" onClick={() => setSelected(new Set())}>
            Clear
          </Button>
        </Group>
      )}

      {list.isError && <Alert color="red">Could not load tracks.</Alert>}

      <Table.ScrollContainer minWidth={900}>
      <Table highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th w={36}>
              <Checkbox
                aria-label="Select all loaded tracks"
                checked={allSelected}
                indeterminate={selected.size > 0 && !allSelected}
                onChange={() => setSelected(allSelected ? new Set() : new Set(rows.map((r) => r.id)))}
              />
            </Table.Th>
            <Table.Th>Title (Fidel)</Table.Th>
            <Table.Th>Title (Latin)</Table.Th>
            <Table.Th>Artist</Table.Th>
            <Table.Th>Year</Table.Th>
            <Table.Th>Era</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Clips</Table.Th>
            <Table.Th>Flags</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((t) => (
            <Table.Tr key={t.id} style={{ cursor: "pointer" }} onClick={() => open(t.id)}>
              <Table.Td onClick={(e) => e.stopPropagation()}>
                <Checkbox aria-label={`Select ${trackName(t)}`} checked={selected.has(t.id)} onChange={() => toggle(t.id)} />
              </Table.Td>
              <Table.Td>{t.titleAm ?? <Text c="dimmed">—</Text>}</Table.Td>
              <Table.Td>{t.titleLatin ?? <Text c="dimmed">—</Text>}</Table.Td>
              <Table.Td>
                {t.artistNameAm}
                {t.artistNameLatin && <Text span c="dimmed"> / {t.artistNameLatin}</Text>}
              </Table.Td>
              <Table.Td>{t.releaseYear ?? "—"}</Table.Td>
              <Table.Td>{eraLabel(generations.data, t.generationId)}</Table.Td>
              <Table.Td>
                <StatusBadge status={t.status} />
              </Table.Td>
              <Table.Td>
                <ClipDots intro={t.introStatus} middle={t.middleStatus} />
              </Table.Td>
              <Table.Td>{t.openFlagCount > 0 ? <Badge color="orange">{t.openFlagCount}</Badge> : <Text c="dimmed">0</Text>}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
      </Table.ScrollContainer>

      {list.isPending && <Loader size="sm" />}
      {list.isSuccess && rows.length === 0 && <Text c="dimmed">No tracks match these filters.</Text>}
      {list.hasNextPage && (
        <Group justify="center">
          <Button variant="default" loading={list.isFetchingNextPage} onClick={() => list.fetchNextPage()}>
            Load more
          </Button>
        </Group>
      )}

      <Modal opened={confirmReject} onClose={() => setConfirmReject(false)} title="Reject selected tracks?">
        <Stack>
          <Text size="sm">
            {selected.size} track{selected.size === 1 ? "" : "s"} will be rejected. A rejected track cannot be approved again.
          </Text>
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setConfirmReject(false)}>
              Cancel
            </Button>
            <Button
              color="red"
              onClick={() => {
                setConfirmReject(false);
                void runBulkAction("reject");
              }}
            >
              Reject
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal
        opened={bulkResults !== null}
        onClose={() => setBulkResults(null)}
        title={bulkResults ? `Bulk ${bulkResults.action}: ${bulkResults.results.filter((r) => r.ok).length} of ${bulkResults.results.length} done` : ""}
        size="lg"
      >
        <Table>
          <Table.Tbody>
            {bulkResults?.results.map((r) => (
              <Table.Tr key={r.item.id}>
                <Table.Td>{trackName(r.item)}</Table.Td>
                <Table.Td>
                  {r.ok ? <Badge color="green">done</Badge> : <Text c="red" size="sm">{r.message}</Text>}
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
        {bulkResults?.results.some((r) => !r.ok) && (
          <Text size="sm" c="dimmed" mt="sm">
            The tracks that failed are still selected.
          </Text>
        )}
      </Modal>
    </Stack>
  );
}
