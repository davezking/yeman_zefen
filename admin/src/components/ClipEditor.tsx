import { Alert, Badge, Button, Group, Loader, Stack, Text } from "@mantine/core";
import { useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import WaveSurfer from "wavesurfer.js";
import RegionsPlugin, { type Region } from "wavesurfer.js/dist/plugins/regions.esm.js";
import { keys, useJobPoll, usePatchClip, useSourceUrl, type Clip } from "../api/catalog";
import { changedStarts, clampStart, nudgeStart, PREVIEW_SECONDS } from "../lib/clipEdit";
import { mmss } from "../lib/format";

type ClipType = "intro" | "middle";
const COLORS: Record<ClipType, string> = { intro: "rgba(34,139,230,0.3)", middle: "rgba(250,176,5,0.3)" };

/**
 * Drag the intro and middle windows over the full source, listen from a window's start, and save. Saving
 * recuts the clips; the job is followed here until it is done, then the clip players get their new files.
 */
export function ClipEditor({ trackId, durationMs, clips }: { trackId: number; durationMs: number | null; clips: Clip[] }) {
  const source = useSourceUrl(trackId);
  if (durationMs == null) return <Text size="sm" c="dimmed">The track's length is unknown, so clip starts cannot be edited.</Text>;
  if (clips.length === 0) return <Text size="sm" c="dimmed">Cut the clips first; then their starts can be edited here.</Text>;
  if (source.isPending) return <Loader size="sm" />;
  if (source.isError) return <Alert color="red">Could not load the source audio: {source.error.message}</Alert>;
  return <Editor trackId={trackId} durationMs={durationMs} clips={clips} url={source.data.url} />;
}

function Editor({ trackId, durationMs, clips, url }: { trackId: number; durationMs: number; clips: Clip[]; url: string }) {
  const qc = useQueryClient();
  const container = useRef<HTMLDivElement>(null);
  const ws = useRef<WaveSurfer | null>(null);
  const regions = useRef<Partial<Record<ClipType, Region>>>({});
  const stopAt = useRef<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const [edited, setEdited] = useState<Record<string, number>>({});
  const [jobs, setJobs] = useState<Partial<Record<ClipType, number | null>>>({});
  const patch = usePatchClip();

  const startOf = useCallback((type: ClipType) => edited[type] ?? clips.find((c) => c.type === type)?.startMs ?? 0, [edited, clips]);
  const lengthOf = (type: ClipType) => clips.find((c) => c.type === type)?.lengthMs ?? 10_000;

  useEffect(() => {
    if (!container.current) return;
    const plugin = RegionsPlugin.create();
    const surfer = WaveSurfer.create({ container: container.current, url, height: 96, waveColor: "#adb5bd", progressColor: "#495057", plugins: [plugin] });
    ws.current = surfer;
    surfer.on("error", (e) => setError(e.message));
    surfer.on("decode", () => {
      for (const clip of clips) {
        const start = clip.startMs / 1000;
        regions.current[clip.type] = plugin.addRegion({ id: clip.type, start, end: start + clip.lengthMs / 1000, color: COLORS[clip.type], drag: true, resize: false, content: clip.type });
      }
      setReady(true);
    });
    // Windows keep their length: dragging only moves the start, which is kept inside the track.
    plugin.on("region-updated", (region) => {
      const type = region.id as ClipType;
      const length = lengthOf(type);
      const startMs = clampStart(region.start * 1000, durationMs, length);
      setEdited((e) => ({ ...e, [type]: startMs }));
      if (Math.abs(region.start * 1000 - startMs) > 1) region.setOptions({ start: startMs / 1000, end: (startMs + length) / 1000 });
    });
    surfer.on("timeupdate", (t) => {
      if (stopAt.current !== null && t >= stopAt.current) {
        stopAt.current = null;
        surfer.pause();
      }
    });
    return () => surfer.destroy();
    // The waveform is built once per signed url; clip rows only change after a save, which keeps the windows.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [url]);

  const moveTo = (type: ClipType, startMs: number) => {
    setEdited((e) => ({ ...e, [type]: startMs }));
    regions.current[type]?.setOptions({ start: startMs / 1000, end: (startMs + lengthOf(type)) / 1000 });
  };

  const playFrom = (type: ClipType, seconds?: number) => {
    const surfer = ws.current;
    if (!surfer) return;
    const start = startOf(type) / 1000;
    stopAt.current = seconds === undefined ? null : start + seconds;
    surfer.setTime(start);
    void surfer.play();
  };

  const dirty = useMemo(() => changedStarts(clips, edited), [clips, edited]);

  const save = async () => {
    setError(null);
    for (const change of dirty) {
      try {
        const res = await patch.mutateAsync({ clipId: change.clipId, startMs: change.startMs });
        setJobs((j) => ({ ...j, [change.type as ClipType]: res.job?.id ?? null }));
      } catch (err) {
        setError(err instanceof Error ? err.message : "Could not save");
      }
    }
    // Keep showing the edited starts until the track has been re-read, so the labels do not jump back.
    await qc.invalidateQueries({ queryKey: keys.track(trackId) });
    setEdited({});
  };

  return (
    <Stack gap="sm">
      <div ref={container} />
      {error && <Alert color="red">{error}</Alert>}
      {!ready && !error && <Loader size="xs" />}
      {(["intro", "middle"] as const).map((type) => {
        const clip = clips.find((c) => c.type === type);
        if (!clip) return null;
        const start = startOf(type);
        return (
          <Stack key={type} gap={4}>
            <Group gap="xs">
              <Badge color={type === "intro" ? "blue" : "yellow"} variant="light" w={70}>{type}</Badge>
              <Text size="sm" ff="monospace">{mmss(start)}</Text>
              <Button size="compact-xs" variant="default" disabled={!ready} onClick={() => playFrom(type)}>Play</Button>
              {PREVIEW_SECONDS.map((s) => (
                <Button key={s} size="compact-xs" variant="default" disabled={!ready} onClick={() => playFrom(type, s)}>{s} s</Button>
              ))}
              <Button size="compact-xs" variant="default" disabled={!ready} onClick={() => ws.current?.pause()}>Stop</Button>
            </Group>
            <Group gap={4}>
              {[-1000, -100, 100, 1000].map((d) => (
                <Button key={d} size="compact-xs" variant="subtle" disabled={!ready} onClick={() => moveTo(type, nudgeStart(start, d, durationMs, lengthOf(type)))}>
                  {d > 0 ? "+" : "−"}{Math.abs(d) >= 1000 ? `${Math.abs(d) / 1000} s` : `${Math.abs(d)} ms`}
                </Button>
              ))}
            </Group>
            <JobStatus jobId={jobs[type] ?? null} saved={type in jobs} onDone={() => void qc.invalidateQueries({ queryKey: keys.track(trackId) })} />
          </Stack>
        );
      })}
      <Group>
        <Button size="xs" disabled={dirty.length === 0 || patch.isPending} loading={patch.isPending} onClick={() => void save()}>
          Save {dirty.length > 0 ? `${dirty.length} clip${dirty.length > 1 ? "s" : ""}` : ""} and recut
        </Button>
        {dirty.length > 0 && <Button size="xs" variant="default" onClick={() => { for (const c of clips) moveTo(c.type, c.startMs); setEdited({}); }}>Reset</Button>}
      </Group>
    </Stack>
  );
}

function JobStatus({ jobId, saved, onDone }: { jobId: number | null; saved: boolean; onDone: () => void }) {
  const job = useJobPoll(jobId);
  const status = job.data?.status;
  const doneFor = useRef<number | null>(null);
  useEffect(() => {
    if (jobId !== null && (status === "succeeded" || status === "failed") && doneFor.current !== jobId) {
      doneFor.current = jobId;
      onDone();
    }
  });
  if (!saved) return null;
  if (jobId === null) return <Text size="xs" c="red">Saved, but the recut job could not be started. Cut this track again from the Jobs page.</Text>;
  if (!status || status === "queued" || status === "running") return <Text size="xs" c="dimmed">Recutting ({status ?? "queued"})…</Text>;
  return status === "succeeded" ? <Text size="xs" c="green">Recut done; the clip below is the new file.</Text> : <Text size="xs" c="red">Recut failed.</Text>;
}
