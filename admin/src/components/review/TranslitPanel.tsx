import { Alert, Badge, Button, Card, Group, SimpleGrid, Stack, Text, TextInput } from "@mantine/core";
import { useState } from "react";
import { usePatchTrack } from "../../api/catalog";
import { useCloseItem, usePatchArtist } from "../../api/review";
import { namePatch, parseTranslit, translitDirection } from "../../lib/review";
import { PlainPanel } from "./PlainPanel";
import { TrackCard } from "./TrackCard";
import { usePanelRun } from "./panelRun";
import type { PanelProps } from "./types";

/**
 * A spelling the transliterator was not sure about. The stored Fidel and Latin are editable; the source and the
 * generated text sit beside them as hints. Accepting saves what changed, then closes the item.
 */
export function TranslitPanel(props: PanelProps) {
  const { item, onClosed } = props;
  const d = parseTranslit(item.details);
  const t = item.track;
  const isTitle = d?.field !== "artist";
  const current = isTitle ? { am: t.titleAm, latin: t.titleLatin } : { am: t.artistNameAm, latin: t.artistNameLatin };

  const [am, setAm] = useState(current.am ?? "");
  const [latin, setLatin] = useState(current.latin ?? "");
  const patchTrack = usePatchTrack(t.id, { silent: true });
  const patchArtist = usePatchArtist(t.artistId);
  const close = useCloseItem();
  const { error, busy, run } = usePanelRun();

  if (!d) return <PlainPanel {...props} />;

  const patch = namePatch({ am, latin }, current);
  const changed = Object.keys(patch).length > 0;
  const fromLatin = translitDirection(d) === "fidel-from-latin";
  const noun = isTitle ? "Title" : "Artist";

  async function accept() {
    const ok = await run(async () => {
      if (changed) {
        if (isTitle) {
          await patchTrack.mutateAsync({
            ...(patch.am !== undefined ? { titleAm: patch.am } : {}),
            ...(patch.latin !== undefined ? { titleLatin: patch.latin } : {}),
          });
        } else {
          await patchArtist.mutateAsync({
            ...(patch.am !== undefined ? { nameAm: patch.am } : {}),
            ...(patch.latin !== undefined ? { nameLatin: patch.latin } : {}),
          });
        }
      }
      await close.mutateAsync({ id: item.id, action: "resolve" });
    });
    if (ok) onClosed(item);
  }

  return (
    <Stack>
      <Group gap="xs">
        <Badge color="orange" variant="light">{noun} spelling uncertain</Badge>
        <Text size="sm" c="dimmed">
          {fromLatin
            ? `The Fidel was generated from the source's Latin${d.confidence !== undefined ? ` (confidence ${Math.round(d.confidence * 100)}%)` : ""}.`
            : `The Latin generated from the source's Fidel differs from the source's Latin${d.distance !== undefined ? ` (${Math.round(d.distance * 100)}% apart)` : ""}.`}
        </Text>
      </Group>

      <SimpleGrid cols={{ base: 1, sm: 2 }}>
        <Card withBorder>
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>From the source (Latin)</Text>
          <Text fw={500} my="xs">{d.source}</Text>
          <Button size="compact-xs" variant="light" onClick={() => setLatin(d.source)}>
            Use as Latin
          </Button>
        </Card>
        <Card withBorder>
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>Generated ({fromLatin ? "Fidel" : "Latin"})</Text>
          <Text fw={500} my="xs">{d.generated}</Text>
          <Button size="compact-xs" variant="light" onClick={() => (fromLatin ? setAm(d.generated) : setLatin(d.generated))}>
            Use as {fromLatin ? "Fidel" : "Latin"}
          </Button>
        </Card>
      </SimpleGrid>

      <SimpleGrid cols={{ base: 1, sm: 2 }}>
        <TextInput label={`${noun} (Fidel)`} value={am} onChange={(e) => setAm(e.currentTarget.value)} />
        <TextInput label={`${noun} (Latin)`} value={latin} onChange={(e) => setLatin(e.currentTarget.value)} />
      </SimpleGrid>
      {!isTitle && (
        <Text size="xs" c="dimmed">
          This changes the artist's name everywhere it is used, not just on this track.
        </Text>
      )}

      {error && <Alert color="red">{error}</Alert>}
      <Group>
        <Button color="green" loading={busy} onClick={() => void accept()}>
          {changed ? "Save and accept" : "Accept"}
        </Button>
        <Button
          variant="default"
          disabled={busy || !changed}
          onClick={() => {
            setAm(current.am ?? "");
            setLatin(current.latin ?? "");
          }}
        >
          Reset
        </Button>
      </Group>

      <TrackCard trackId={t.id} heading="Track" />
    </Stack>
  );
}
