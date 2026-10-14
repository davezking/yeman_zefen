export interface NavItem {
  label: string;
  path: string;
}

// Order matches the admin sidebar. Each later sprint replaces its placeholder page.
export const navItems: NavItem[] = [
  { label: "Tracks", path: "/tracks" },
  { label: "Review queue", path: "/review" },
  { label: "Artists", path: "/artists" },
  { label: "Packs", path: "/packs" },
  { label: "Jobs", path: "/jobs" },
  { label: "Reports", path: "/reports" },
  { label: "Analytics", path: "/analytics" },
  { label: "Moderation", path: "/moderation" },
];
