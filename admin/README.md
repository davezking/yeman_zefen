# admin/

The admin dashboard: a Vite + React + TypeScript SPA with Mantine, TanStack Query and React Router. It calls the
Worker's `/admin/*` routes with the Cloudflare Access cookie. Hosted on Cloudflare Pages behind Access. See
`docs/ops.md` for the Pages settings.

## Commands

| Command | What it does |
|---|---|
| `npm ci` | Install from the lockfile |
| `npm run dev` | Dev server on `http://localhost:5173` |
| `npm run typecheck` | `tsc -b` for the app, the tests and the Vite config |
| `npm test` | Vitest unit tests (`test/`) |
| `npm run build` | Typecheck, then production build into `dist/`. Needs `VITE_API_BASE` set, and fails without it |

## Local setup

1. Start the Worker: `cd ../api && npm run dev` (port 8787). Set `DEV_ADMIN_EMAIL` in `api/.dev.vars`, and seed that
   email into `admin_users` (see `docs/ops.md`).
2. Optional: copy `.env.example` to `.env.local` to change `VITE_API_BASE`.
3. Start the SPA: `npm run dev`, then open `http://localhost:5173`. The header shows your email and role.

## Layout

- `src/api/client.ts`: typed fetch wrapper. It sends credentials, validates responses with zod, and throws
  `ApiError` from the Worker's `{ error }` body. Pass JSON as `json` (sets the content type) and anything else, such
  as FormData, as `body`. Use the `noContent` schema for 204 responses.
- `src/queryClient.ts`: shows every failed query or mutation as a Mantine notification, with the Worker's request id
  when there is one.
- `src/api/catalog.ts`: schemas and TanStack Query hooks for tracks, artists, eras, genres and review items.
- `src/layout/`: the app shell and sidebar. `nav.ts` is the list of routes.
- `src/pages/`: `TracksPage` (table, filters, bulk actions), `TrackDetailPage` (editor) and `ReviewPage` (the review
  queue; its panels are in `src/components/review/`). The other routes are placeholders that later sprints replace.
- `src/lib/`: logic with tests: the form-to-patch diff (`trackForm.ts`), the filters kept in the URL
  (`trackFilters.ts`), the bulk runner (`bulk.ts`) and review-item details and edits (`review.ts`).

## Tracks

`/tracks` lists tracks with filters (status, era, genre, search). They live in the URL, so the editor can walk the
same filtered list. Select rows to approve or reject in bulk; each row's result is listed, and failed rows stay selected.

`/tracks/:id` edits a track. Only the fields you changed are sent, because the API pins every field it receives
against re-scrapes. Keyboard shortcuts (they do not fire while you type in a field):

| Key | Does |
|---|---|
| `j` / `k` | Next / previous track in the current filter |
| `a` | Approve, then move to the next track |
| `e` | Focus the Fidel title |
| `Ctrl/⌘ + Enter` | Save |

`j`, `k` and `a` refuse to act while the form has unsaved changes. If a track can't be approved (a clip missing or
not ready), the reason shows next to the buttons and you stay on the track.

To try it with data and audio locally, see "Track editor API" in `docs/ops.md`.

## Review queue

`/review` has a tab per flag reason, each with its count and its items oldest first. The panel on the right resolves
the chosen item (what each one does is in "Review queue API" in `docs/ops.md`). Closing an item moves on to the next
in the tab, and closing the last open item of a track offers to approve it. Merging artists is for admins; the button
is disabled for editors.
