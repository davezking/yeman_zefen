import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Code,
  Group,
  Loader,
  Modal,
  MultiSelect,
  NumberInput,
  Select,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import { getHotkeyHandler, useHotkeys } from "@mantine/hooks";
import { notifications } from "@mantine/notifications";
import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  fetchTrackAfter,
  useCloseReviewItem,
  useGenerations,
  useGenres,
  useEnsureTrack,
  usePatchTrack,
  usePrefetchTrack,
  useTrack,
  useTrackAction,
  useTrackList,
  type Clip,
  type TrackAction,
  type TrackDetail,
} from "../api/catalog";
import { ApiError } from "../api/client";
import { ArtistPicker } from "../components/ArtistPicker";
import { StatusBadge, statusLabel, trackName } from "../components/TrackBits";
import { filtersFromParams } from "../lib/trackFilters";
import { mmss } from "../lib/format";
import { buildPatch, toForm, type FormValues } from "../lib/trackForm";

const REASON_LABEL: Record<string, string> = {
  translit_uncertain: "Transliteration uncertain",
  possible_duplicate: "Possible duplicate",
  missing_audio: "Missing audio",
  short_audio: "Short audio",
  era_unknown: "Era unknown",
};

const isHttp = (u: string) => /^https?:\/\//i.test(u);

/**
 * Where the page is heading, shared by every track's editor. A key pressed after we start moving but before the
 * next track is mounted is still handled by the editor on screen, so moves are worked out from `at`, not from
 * the track being shown. `token` numbers each move, and `settled` is the last one that completed.
 */
interface Nav {
  at: number;
  token: number;
  settled: number;
  /** The track an approve or reject is in flight for, so a repeated key cannot act on it twice. */
  busy: number | null;
}

export function TrackDetailPage() {
  const id = Number(useParams().id);
  const track = useTrack(id);
  const nav = useRef<Nav>({ at: id, token: 0, settled: 0, busy: null });
  // Follow the URL when we did not cause the change (back button, a link), but never while a move is in flight.
  // Read the URL as it is now: this effect can run after we have already issued the next move.
  useEffect(() => {
    const now = Number(window.location.pathname.split("/").pop());
    if (nav.current.token === nav.current.settled && Number.isInteger(now) && now > 0) nav.current.at = now;
  }, [id]);
  if (!Number.isInteger(id) || id <= 0) return <Alert color="red">That is not a track id.</Alert>;
  if (track.isPending) return <Loader size="sm" />;
  if (track.isError) {
    return (
      <Stack>
        <Alert color="red">Could not load track {id}.</Alert>
        <Anchor component={Link} to="/tracks">
          Back to tracks
        </Anchor>
      </Stack>
    );
  }
  // Keyed by id, so moving to another track starts from a clean form.
  return <TrackEditor key={id} id={id} detail={track.data} nav={nav} />;
}

function TrackEditor({ id, detail, nav }: { id: number; detail: TrackDetail; nav: React.RefObject<Nav> }) {
  const navigate = useNavigate();
  const [sp] = useSearchParams();
  const generations = useGenerations();
  const genres = useGenres();
  const patchTrack = usePatchTrack(id);
  const action = useTrackAction();
  const closeItem = useCloseReviewItem(id);
  const prefetch = usePrefetchTrack();
  const ensureTrack = useEnsureTrack();
  const filters = filtersFromParams(sp);
  const list = useTrackList(filters);

  // `base` is the version of the track the form was filled from. The patch is worked out against it, not against
  // the latest fetch, so a change made elsewhere (another admin, a re-scrape) never shows up as the admin's own edit
  // and is never written back over. With no edits in progress, the form simply follows the latest version.
  const [base, setBase] = useState<TrackDetail>(detail);
  const [values, setValues] = useState<FormValues>(() => toForm(detail));
  const patch = buildPatch(values, base);
  const dirty = Object.keys(patch).length > 0;
  const changedElsewhere = detail !== base;
  useEffect(() => {
    if (detail === base || dirty) return;
    setBase(detail);
    setValues(toForm(detail));
    // Runs when a new version arrives; `dirty` is read at that moment on purpose.
  }, [detail]);
  const reset = (d: TrackDetail) => {
    setBase(d);
    setValues(toForm(d));
  };
  const set = <K extends keyof FormValues>(k: K, v: FormValues[K]) => setValues((prev) => ({ ...prev, [k]: v }));
  const titleRef = useRef<HTMLInputElement>(null);
  const [actionError, setActionError] = useState<{ action: TrackAction; message: string } | null>(null);
  const [confirmReject, setConfirmReject] = useState(false);

  // Walk the list the admin came from: same filters, same order.
  const ids = list.data?.pages.flatMap((p) => p.items.map((t) => t.id)) ?? [];
  const around = (from: number) => {
    const i = ids.indexOf(from);
    return { index: i, prev: i > 0 ? ids[i - 1] : undefined, next: i >= 0 ? ids[i + 1] : undefined };
  };
  const { index, prev: prevId, next: nextId } = around(id);
  useEffect(() => {
    if (nextId) prefetch(nextId);
    if (prevId) prefetch(prevId);
    // Only a change of neighbour should prefetch.
  }, [nextId, prevId]);

  const listPath = { pathname: "/tracks", search: sp.toString() };
  const go = (to: number) => {
    nav.current.at = to;
    // Switch only once the destination is loaded: this page stays mounted, and keeps hearing keys, until then.
    // If keys arrive faster than tracks load, only the latest target is navigated to.
    const token = ++nav.current.token;
    void ensureTrack(to)
      .catch(() => undefined) // the destination page shows its own error
      .then(() => {
        if (token !== nav.current.token) return;
        nav.current.settled = token;
        void navigate({ pathname: `/tracks/${to}`, search: sp.toString() });
      });
  };
  const blockedByEdits = () => {
    if (!dirty) return false;
    notifications.show({ color: "yellow", message: "You have unsaved changes. Save them first (Ctrl+Enter), or reload to discard." });
    return true;
  };

  /** The next track after `from` in this filter: from the loaded list when it is there, else from the API. */
  async function nextAfter(from: number): Promise<number | undefined> {
    const here = around(from);
    if (here.next) return here.next;
    if (here.index >= 0 && !list.hasNextPage) return undefined; // the last track of the whole list
    // Keep the loaded list growing, so k can come back here.
    if (list.hasNextPage && !list.isFetchingNextPage) void list.fetchNextPage();
    return fetchTrackAfter(filters, from).catch(() => undefined);
  }

  async function goNext() {
    if (blockedByEdits()) return;
    const from = nav.current.at;
    const next = await nextAfter(from);
    // Only move if nothing else moved the page while we were asking.
    if (next && nav.current.at === from) go(next);
  }
  const goPrev = () => {
    const { prev } = around(nav.current.at);
    if (!blockedByEdits() && prev) go(prev);
  };

  async function save() {
    if (!dirty || patchTrack.isPending) return;
    const saved = await patchTrack.mutateAsync(patch).catch(() => null);
    if (saved) {
      reset(saved);
      notifications.show({ color: "green", message: "Saved" });
    }
  }

  async function act(kind: TrackAction) {
    // Act on the track the admin is looking at, which is the one we are heading to if a move is under way.
    const target = nav.current.at;
    if (target <= 0 || nav.current.busy === target) return;
    const onScreen = target === id;
    if (onScreen && blockedByEdits()) return;
    nav.current.busy = target;
    if (onScreen) setActionError(null);
    try {
      await action.mutateAsync({ id: target, action: kind });
    } catch (err) {
      const message = err instanceof ApiError ? err.message : "Request failed";
      if (onScreen) setActionError({ action: kind, message });
      else notifications.show({ color: "red", title: `Can't ${kind} track ${target}`, message });
      return;
    } finally {
      nav.current.busy = null;
    }
    notifications.show({
      color: kind === "approve" ? "green" : "orange",
      message: `${kind === "approve" ? "Approved" : "Rejected"} ${onScreen ? trackName(detail.track) : `track ${target}`}`,
    });
    // Move on to the next track in the list (the last one goes back to the list), unless the admin already moved.
    if (nav.current.at !== target) return;
    const next = await nextAfter(target);
    if (nav.current.at !== target) return;
    if (next) go(next);
    else {
      nav.current.at = 0;
      nav.current.settled = ++nav.current.token;
      void navigate(listPath);
    }
  }

  // Shortcuts belong to the page, not to a dialog on top of it (the reject confirmation, a new artist).
  const page = (fn: () => void) => () => {
    if (!document.querySelector('[role="dialog"]')) fn();
  };
  useHotkeys([
    ["j", page(() => void goNext())],
    ["k", page(goPrev)],
    ["a", page(() => void act("approve"))],
    ["e", page(() => titleRef.current?.focus())],
  ]);

  const status = detail.track.status;
  const canDecide = status === "ingested" || status === "needs_review";
  const era = generations.data?.find((g) => String(g.id) === values.generationId);

  return (
    <Stack onKeyDown={getHotkeyHandler([["mod+Enter", () => void save()]])}>
      <Group justify="space-between">
        <Group>
          <Anchor component={Link} to={listPath} size="sm">
            ← Tracks
          </Anchor>
          <Title order={2}>{trackName(detail.track)}</Title>
          <StatusBadge status={status} />
        </Group>
        <Group gap="xs">
          <Button size="xs" variant="default" disabled={!prevId} onClick={goPrev}>
            ‹ Prev (k)
          </Button>
          <Text size="sm" c="dimmed">
            {index >= 0 ? `${index + 1} of ${ids.length}${list.hasNextPage ? "+" : ""}` : "not in this list"}
          </Text>
          <Button size="xs" variant="default" disabled={!nextId && !list.hasNextPage} onClick={() => void goNext()}>
            Next (j) ›
          </Button>
        </Group>
      </Group>

      <SimpleGrid cols={{ base: 1, md: 2 }} spacing="lg">
        <Stack>
          <TextInput ref={titleRef} label="Title (Fidel)" value={values.titleAm} onChange={(e) => set("titleAm", e.currentTarget.value)} />
          <TextInput label="Title (Latin)" value={values.titleLatin} onChange={(e) => set("titleLatin", e.currentTarget.value)} />
          <ArtistPicker value={values.artist} onChange={(a) => set("artist", a)} />
          <TextInput label="Album" value={values.album} onChange={(e) => set("album", e.currentTarget.value)} />
          <NumberInput
            label="Release year"
            min={1900}
            max={2100}
            allowDecimal={false}
            allowNegative={false}
            value={values.releaseYear}
            onChange={(v) => set("releaseYear", typeof v === "number" ? v : "")}
          />
          <Select
            label={
              <Group gap={6}>
                Era
                {values.generationId !== null && (detail.track.generationOverridden || patch.generationId !== undefined) && (
                  <Badge size="xs" color="grape" variant="light">
                    overridden
                  </Badge>
                )}
              </Group>
            }
            description={values.generationId === null ? "Follows the release year" : "Clear to follow the release year again"}
            placeholder="Follows the release year"
            clearable
            data={(generations.data ?? []).map((g) => ({
              value: String(g.id),
              label: `${g.nameEn}${g.yearFrom || g.yearTo ? ` (${g.yearFrom ?? "…"}–${g.yearTo ?? "…"})` : ""}`,
            }))}
            value={values.generationId}
            // Clicking the chosen era again must pin it, not clear it: clearing is the × button's job.
            allowDeselect={false}
            onOptionSubmit={(v) => setValues((prev) => ({ ...prev, generationId: v, eraPicked: true }))}
            onChange={(v) => setValues((prev) => ({ ...prev, generationId: v, eraPicked: v !== null && prev.eraPicked }))}
          />
          {era === undefined && values.generationId !== null && <Text size="xs" c="dimmed">Loading eras…</Text>}
          <MultiSelect
            label="Genres"
            searchable
            data={(genres.data ?? []).map((g) => ({ value: String(g.id), label: g.nameEn }))}
            value={values.genreIds}
            onChange={(v) => set("genreIds", v)}
          />
          <Group>
            <Button loading={patchTrack.isPending} disabled={!dirty} onClick={() => void save()}>
              Save
            </Button>
            <Button variant="default" disabled={!dirty} onClick={() => reset(detail)}>
              Discard
            </Button>
            <Text size="xs" c="dimmed">
              Ctrl+Enter saves
            </Text>
          </Group>
          {dirty && changedElsewhere && (
            <Text size="xs" c="orange">
              This track was changed elsewhere since you opened it. Saving sends only the fields you edited; Discard
              shows the latest version.
            </Text>
          )}
          {detail.track.sourceUrl && (
            <Text size="sm">
              Source:{" "}
              {isHttp(detail.track.sourceUrl) ? (
                <Anchor href={detail.track.sourceUrl} target="_blank" rel="noreferrer noopener">
                  {detail.track.sourceUrl}
                </Anchor>
              ) : (
                <Code>{detail.track.sourceUrl}</Code>
              )}
            </Text>
          )}
        </Stack>

        <Stack>
          <Card withBorder>
            <Stack gap="sm">
              <Title order={4}>Clips</Title>
              {(["intro", "middle"] as const).map((type) => (
                <ClipRow key={type} type={type} clip={detail.clips.find((c) => c.type === type)} />
              ))}
            </Stack>
          </Card>

          <Card withBorder>
            <Stack gap="sm">
              <Title order={4}>Open review items</Title>
              {detail.openReviewItems.length === 0 && <Text size="sm" c="dimmed">None.</Text>}
              {detail.openReviewItems.map((item) => (
                <Stack key={item.id} gap={4}>
                  <Group justify="space-between">
                    <Badge color="orange" variant="light">
                      {REASON_LABEL[item.reason] ?? item.reason}
                    </Badge>
                    <Group gap="xs">
                      <Button
                        size="compact-xs"
                        color="green"
                        variant="light"
                        disabled={closeItem.isPending}
                        onClick={() => closeItem.mutate({ id: item.id, action: "resolve" })}
                      >
                        Resolve
                      </Button>
                      <Button
                        size="compact-xs"
                        variant="default"
                        disabled={closeItem.isPending}
                        onClick={() => closeItem.mutate({ id: item.id, action: "dismiss" })}
                      >
                        Dismiss
                      </Button>
                    </Group>
                  </Group>
                  {item.detailsJson && <Code block>{item.detailsJson}</Code>}
                </Stack>
              ))}
            </Stack>
          </Card>

          <Card withBorder>
            <Stack gap="sm">
              <Title order={4}>Decision</Title>
              {actionError && (
                <Alert color="red" title={actionError.action === "approve" ? "Can't approve" : "Can't reject"}>
                  {actionError.message}
                </Alert>
              )}
              <Group>
                <Button color="green" disabled={!canDecide} loading={action.isPending && action.variables?.action === "approve"} onClick={() => void act("approve")}>
                  Approve (a)
                </Button>
                <Button color="red" variant="light" disabled={!canDecide} onClick={() => setConfirmReject(true)}>
                  Reject
                </Button>
              </Group>
              {!canDecide && <Text size="sm" c="dimmed">This track is {statusLabel(status)}, so it can't be approved or rejected here.</Text>}
            </Stack>
          </Card>
        </Stack>
      </SimpleGrid>

      <Modal opened={confirmReject} onClose={() => setConfirmReject(false)} title="Reject this track?">
        <Stack>
          <Text size="sm">{trackName(detail.track)} will be rejected. A rejected track cannot be approved again.</Text>
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setConfirmReject(false)}>
              Cancel
            </Button>
            <Button
              color="red"
              onClick={() => {
                setConfirmReject(false);
                void act("reject");
              }}
            >
              Reject
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}

function ClipRow({ type, clip }: { type: "intro" | "middle"; clip: Clip | undefined }) {
  const name = type === "intro" ? "Intro" : "Middle";
  if (!clip) {
    return (
      <Group>
        <Text fw={500} w={60}>{name}</Text>
        <Badge color="gray" variant="light">not cut yet</Badge>
      </Group>
    );
  }
  const color = clip.status === "ready" ? "green" : clip.status === "failed" ? "red" : "yellow";
  return (
    <Stack gap={4}>
      <Group>
        <Text fw={500} w={60}>{name}</Text>
        <Badge color={color} variant="light">{clip.status === "pending" ? "pending: cut job" : clip.status}</Badge>
        <Text size="xs" c="dimmed">starts at {mmss(clip.startMs)}, {(clip.lengthMs / 1000).toFixed(0)} s</Text>
      </Group>
      {clip.url ? (
        <audio controls preload="none" src={clip.url} style={{ width: "100%" }} />
      ) : (
        <Text size="sm" c="dimmed">No file to play until the clip is ready.</Text>
      )}
    </Stack>
  );
}
