import { Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "./layout/AppShell";
import { PlaceholderPage } from "./pages/PlaceholderPage";
import { navItems } from "./layout/nav";

export function App() {
  return (
    <AppShell>
      <Routes>
        <Route index element={<Navigate to="/tracks" replace />} />
        {navItems.map((item) => (
          <Route
            key={item.path}
            path={item.path.slice(1)}
            element={<PlaceholderPage title={item.label} />}
          />
        ))}
        <Route path="*" element={<PlaceholderPage title="Not found" />} />
      </Routes>
    </AppShell>
  );
}
