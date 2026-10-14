import { createTheme } from "@mantine/core";

// Noto Sans Ethiopic is loaded globally (see main.tsx) so Fidel renders everywhere,
// including the Latin UI text around it.
export const theme = createTheme({
  fontFamily: '"Noto Sans Ethiopic", system-ui, sans-serif',
  headings: { fontFamily: '"Noto Sans Ethiopic", system-ui, sans-serif' },
});
