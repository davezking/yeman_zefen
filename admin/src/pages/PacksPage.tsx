import { Alert, Badge, Button, Card, Code, Group, Loader, Modal, Select, Stack, Table, Text, TextInput, Title } from "@mantine/core";
import { useState } from "react";
import { useGenerations, useGenres } from "../api/catalog";
import { useCreatePack, usePackDiff, usePacks, usePublishPack, type Pack, type PackDiff } from "../api/packs";
import { megabytes, SLUG_RE } from "../lib/packs";

export function PacksPage() {
  const packs = usePacks();
  return (
    <Stack>
      <Title order={2}>Packs</Title>
      <NewPackForm />
      {packs.isPending && <Loader size="sm" />}
      {packs.isError && <Alert color="red">Could not load packs: {packs.error.message}</Alert>}
      {packs.data?.length === 0 && <Text c="dimmed">No packs yet.</Text>}
      {packs.data?.map((p) => <PackCard key={p.id} pack={p} />)}
    </Stack>
  );
}

function NewPackForm() {
  const generations = useGenerations();
  const genres = useGenres();
  const create = useCreatePack();
  const [slug, setSlug] = useState("");
  const [nameAm, setNameAm] = useState("");
  const [nameEn, setNameEn] = useState("");
  const [generationId, setGenerationId] = useState<string | null>(null);
  const [genreId, setGenreId] = useState<string | null>(null);
  const valid = SLUG_RE.test(slug) && nameAm.trim() !== "" && nameEn.trim() !== "";

  return (
    <Card withBorder>
      <Stack gap="sm">
        <Title order={4}>New pack</Title>
        <Group align="flex-end">
          <TextInput label="Slug" placeholder="golden-era" value={slug} onChange={(e) => setSlug(e.currentTarget.value)} error={slug !== "" && !SLUG_RE.test(slug) ? "lowercase letters, digits, dashes" : undefined} />
          <TextInput label="Name (Amharic)" value={nameAm} onChange={(e) => setNameAm(e.currentTarget.value)} />
          <TextInput label="Name (English)" value={nameEn} onChange={(e) => setNameEn(e.currentTarget.value)} />
          <Select label="Era filter" clearable placeholder="Any era" value={generationId} onChange={setGenerationId} data={(generations.data ?? []).map((g) => ({ value: String(g.id), label: g.nameEn }))} />
          <Select label="Genre filter" clearable placeholder="Any genre" value={genreId} onChange={setGenreId} data={(genres.data ?? []).map((g) => ({ value: String(g.id), label: g.nameEn }))} />
          <Button
            disabled={!valid}
            loading={create.isPending}
            onClick={() =>
              create.mutate(
                { slug, nameAm: nameAm.trim(), nameEn: nameEn.trim(), generationId: generationId ? Number(generationId) : null, genreId: genreId ? Number(genreId) : null },
                { onSuccess: () => { setSlug(""); setNameAm(""); setNameEn(""); setGenerationId(null); setGenreId(null); } },
              )
            }
          >
            Create
          </Button>
        </Group>
        {create.isError && <Alert color="red">{create.error.message}</Alert>}
      </Stack>
    </Card>
  );
}

function PackCard({ pack }: { pack: Pack }) {
  const [confirming, setConfirming] = useState(false);
  const publish = usePublishPack();
  return (
    <Card withBorder>
      <Stack gap="sm">
        <Group justify="space-between">
          <Group>
            <Title order={4}>{pack.nameEn}</Title>
            <Text>{pack.nameAm}</Text>
            <Code>{pack.slug}</Code>
            <Badge variant="light" color={pack.currentVersion ? "green" : "gray"}>{pack.currentVersion ? `v${pack.currentVersion} live` : "unpublished"}</Badge>
          </Group>
          <Group>
            <Text size="sm" c="dimmed">{pack.eligibleCount} eligible track{pack.eligibleCount === 1 ? "" : "s"}</Text>
            <Button size="xs" disabled={pack.eligibleCount === 0} onClick={() => { publish.reset(); setConfirming(true); }}>Publish new version</Button>
          </Group>
        </Group>
        {publish.isSuccess && <Alert color="green">Published v{publish.data.published.version}.</Alert>}
        {publish.isError && !confirming && <Alert color="red">{publish.error.message}</Alert>}
        {pack.versions.length > 0 && (
          <Table withTableBorder>
            <Table.Thead>
              <Table.Tr><Table.Th>Version</Table.Th><Table.Th>Tracks</Table.Th><Table.Th>Size</Table.Th><Table.Th>Published</Table.Th><Table.Th>By</Table.Th><Table.Th>Manifest</Table.Th></Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {pack.versions.map((v) => (
                <Table.Tr key={v.version}>
                  <Table.Td>v{v.version}{v.version === pack.currentVersion && " (current)"}</Table.Td>
                  <Table.Td>{v.trackCount}</Table.Td>
                  <Table.Td>{megabytes(v.totalBytes)}</Table.Td>
                  <Table.Td>{new Date(v.publishedAt).toLocaleString()}</Table.Td>
                  <Table.Td>{v.publishedBy ?? "–"}</Table.Td>
                  <Table.Td><a href={v.manifestUrl} target="_blank" rel="noreferrer noopener">open</a></Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </Stack>
      {confirming && <PublishConfirm pack={pack} publishing={publish.isPending} error={publish.isError ? publish.error.message : null} onClose={() => setConfirming(false)} onConfirm={() => publish.mutate(pack.id, { onSuccess: () => setConfirming(false) })} />}
    </Card>
  );
}

const trackLabel = (t: { id: number; titleAm: string | null; titleLatin: string | null }) => t.titleLatin || t.titleAm || `Track ${t.id}`;

function PublishConfirm({ pack, publishing, error, onClose, onConfirm }: { pack: Pack; publishing: boolean; error: string | null; onClose: () => void; onConfirm: () => void }) {
  const diff = usePackDiff(pack.id);
  return (
    <Modal opened onClose={onClose} title={`Publish ${pack.nameEn}`} size="lg">
      <Stack>
        {diff.isPending && <Loader size="sm" />}
        {diff.isError && <Alert color="red">Could not work out the changes: {diff.error.message}</Alert>}
        {diff.data && <DiffView diff={diff.data} />}
        {error && <Alert color="red">{error}</Alert>}
        <Text size="xs" c="dimmed">A published version is never changed. Players get this one the next time they refresh their packs.</Text>
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button color="green" loading={publishing} disabled={!diff.data || diff.data.eligibleCount === 0} onClick={onConfirm}>
            {diff.data ? `Publish v${diff.data.nextVersion}` : "Publish"}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function DiffView({ diff }: { diff: PackDiff }) {
  const unchanged = diff.currentVersion !== null && diff.added.length === 0 && diff.removed.length === 0;
  return (
    <Stack gap="xs">
      <Text size="sm">
        {diff.eligibleCount} tracks will be in this version{diff.currentVersion !== null && `, against v${diff.currentVersion} now`}.
      </Text>
      {unchanged && <Alert color="yellow">Nothing changed since v{diff.currentVersion}. Publishing would create an identical version.</Alert>}
      <TrackList title="Added" color="green" tracks={diff.added} />
      <TrackList title="Removed" color="red" tracks={diff.removed} />
    </Stack>
  );
}

function TrackList({ title, color, tracks }: { title: string; color: string; tracks: PackDiff["added"] }) {
  if (tracks.length === 0) return null;
  return (
    <Stack gap={2}>
      <Badge color={color} variant="light">{title}: {tracks.length}</Badge>
      <Text size="sm" style={{ maxHeight: 160, overflowY: "auto" }}>{tracks.map(trackLabel).join(", ")}</Text>
    </Stack>
  );
}
