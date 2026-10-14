import { Stack, Text, Title } from "@mantine/core";

// Stands in for a page that a later sprint builds.
export function PlaceholderPage({ title }: { title: string }) {
  return (
    <Stack>
      <Title order={2}>{title}</Title>
      <Text c="dimmed">Coming soon.</Text>
    </Stack>
  );
}
