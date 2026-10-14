import { Alert, Button, Group, Modal, Select, Stack, TextInput } from "@mantine/core";
import { useDebouncedValue } from "@mantine/hooks";
import { notifications } from "@mantine/notifications";
import { useMemo, useState } from "react";
import { useArtistSearch, useCreateArtist, type Artist } from "../api/catalog";
import { ApiError } from "../api/client";

const label = (a: Artist) => (a.nameLatin ? `${a.nameAm} / ${a.nameLatin}` : a.nameAm);

/** Search-as-you-type artist select, with a way to create an artist that is not in the catalog yet. */
export function ArtistPicker({ value, onChange }: { value: Artist; onChange: (artist: Artist) => void }) {
  const [search, setSearch] = useState("");
  const [debounced] = useDebouncedValue(search.trim(), 250);
  const results = useArtistSearch(debounced);
  const [creating, setCreating] = useState(false);

  // The chosen artist is always an option, so its label shows even when the search results move on.
  const artists = useMemo(() => {
    const byId = new Map<number, Artist>([[value.id, value]]);
    for (const a of results.data ?? []) byId.set(a.id, a);
    return [...byId.values()];
  }, [results.data, value]);

  return (
    <Stack gap={4}>
      <Select
        label="Artist"
        searchable
        data={artists.map((a) => ({ value: String(a.id), label: label(a) }))}
        value={String(value.id)}
        searchValue={search}
        onSearchChange={setSearch}
        // The server does the matching (it also searches Latin names), so show whatever it returned.
        filter={({ options }) => options}
        nothingFoundMessage="No artist found"
        allowDeselect={false}
        onChange={(v) => {
          const picked = artists.find((a) => String(a.id) === v);
          if (picked) onChange(picked);
        }}
      />
      <Group>
        <Button variant="subtle" size="compact-xs" onClick={() => setCreating(true)}>
          Create new artist
        </Button>
      </Group>
      <NewArtistModal
        opened={creating}
        initialName={debounced}
        onClose={() => setCreating(false)}
        onCreated={(a) => {
          setCreating(false);
          setSearch("");
          onChange(a);
          notifications.show({ color: "green", message: `Created ${label(a)}` });
        }}
      />
    </Stack>
  );
}

function NewArtistModal({
  opened,
  initialName,
  onClose,
  onCreated,
}: {
  opened: boolean;
  initialName: string;
  onClose: () => void;
  onCreated: (artist: Artist) => void;
}) {
  const create = useCreateArtist();
  const [nameAm, setNameAm] = useState("");
  const [nameLatin, setNameLatin] = useState("");
  const error = create.error instanceof ApiError ? create.error.message : create.error ? "Could not create the artist" : null;

  return (
    <Modal
      opened={opened}
      onClose={onClose}
      title="New artist"
      onEnterTransitionEnd={() => setNameAm((n) => n || initialName)}
      onExitTransitionEnd={() => {
        setNameAm("");
        setNameLatin("");
        create.reset();
      }}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          create.mutate({ nameAm, ...(nameLatin.trim() ? { nameLatin } : {}) }, { onSuccess: onCreated });
        }}
      >
        <Stack>
          {error && <Alert color="red">{error}</Alert>}
          <TextInput label="Name (Fidel)" required data-autofocus value={nameAm} onChange={(e) => setNameAm(e.currentTarget.value)} />
          <TextInput label="Name (Latin)" value={nameLatin} onChange={(e) => setNameLatin(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" loading={create.isPending} disabled={!nameAm.trim()}>
              Create
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
