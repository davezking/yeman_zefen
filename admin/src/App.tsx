import { Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "./layout/AppShell";
import { PacksPage } from "./pages/PacksPage";
import { PlaceholderPage } from "./pages/PlaceholderPage";
import { ReviewPage } from "./pages/ReviewPage";
import { TrackDetailPage } from "./pages/TrackDetailPage";
import { TracksPage } from "./pages/TracksPage";
import { navItems } from "./layout/nav";

export function App() {
  return (
    <AppShell>
      <Routes>
        <Route index element={<Navigate to="/tracks" replace />} />
        <Route path="tracks" element={<TracksPage />} />
        <Route path="tracks/:id" element={<TrackDetailPage />} />
        <Route path="review" element={<ReviewPage />} />
        <Route path="packs" element={<PacksPage />} />
        {navItems
          .filter((item) => item.path !== "/tracks" && item.path !== "/review" && item.path !== "/packs")
          .map((item) => (
            <Route key={item.path} path={item.path.slice(1)} element={<PlaceholderPage title={item.label} />} />
          ))}
        <Route path="*" element={<PlaceholderPage title="Not found" />} />
      </Routes>
    </AppShell>
  );
}
