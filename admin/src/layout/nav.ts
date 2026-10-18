export interface NavItem {
  label: string;
  path: string;
  /** Shown only to the admin role (the editor role is refused by the Worker). */
  adminOnly?: boolean;
}

// Order matches the admin sidebar. Each later sprint replaces its placeholder page.
export const navItems: NavItem[] = [
  { label: "Tracks", path: "/tracks" },
  { label: "Review queue", path: "/review" },
  { label: "Artists", path: "/artists" },
  { label: "Packs", path: "/packs" },
  { label: "Jobs", path: "/jobs" },
  { label: "Reports", path: "/reports", adminOnly: true },
  { label: "Analytics", path: "/analytics" },
  { label: "Moderation", path: "/moderation", adminOnly: true },
];
