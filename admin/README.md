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
- `src/layout/`: the app shell and sidebar. `nav.ts` is the list of routes.
- `src/pages/`: placeholder pages. Later sprints replace them.
