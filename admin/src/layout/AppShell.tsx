import { AppShell as MantineAppShell, Badge, Burger, Group, NavLink, Text, Title } from "@mantine/core";
import { useDisclosure } from "@mantine/hooks";
import type { ReactNode } from "react";
import { NavLink as RouterNavLink, useLocation } from "react-router-dom";
import { useWhoami } from "../api/whoami";
import { navItems } from "./nav";

export function AppShell({ children }: { children: ReactNode }) {
  const location = useLocation();
  const whoami = useWhoami();
  // Below the "sm" breakpoint the navbar covers the page, so it starts closed and the burger toggles it.
  const [navOpened, { toggle: toggleNav, close: closeNav }] = useDisclosure(false);

  return (
    <MantineAppShell
      header={{ height: 56 }}
      navbar={{ width: 220, breakpoint: "sm", collapsed: { mobile: !navOpened } }}
      padding="md"
    >
      <MantineAppShell.Header>
        <Group h="100%" px="md" justify="space-between">
          <Group gap="sm">
            <Burger opened={navOpened} onClick={toggleNav} hiddenFrom="sm" size="sm" aria-label="Toggle navigation" />
            <Title order={4}>Admin</Title>
          </Group>
          {whoami.data && (
            <Group gap="xs">
              <Text size="sm">{whoami.data.email}</Text>
              <Badge variant="light">{whoami.data.role}</Badge>
            </Group>
          )}
        </Group>
      </MantineAppShell.Header>

      <MantineAppShell.Navbar p="xs">
        <Text fw={700} size="lg" px="xs" pb="sm">
          የማን ዘፈን
        </Text>
        {navItems.map((item) => (
          <NavLink
            key={item.path}
            component={RouterNavLink}
            to={item.path}
            label={item.label}
            active={location.pathname.startsWith(item.path)}
            onClick={closeNav}
          />
        ))}
      </MantineAppShell.Navbar>

      <MantineAppShell.Main>{children}</MantineAppShell.Main>
    </MantineAppShell>
  );
}
