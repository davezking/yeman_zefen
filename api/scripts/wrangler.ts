// Runs this project's wrangler with Node itself. `execFileSync("npx", ...)` fails on Windows (`spawnSync npx
// ENOENT`: npx is npx.cmd, which Node only starts through a shell), and going through a shell would mangle
// arguments such as SQL with quotes. Starting wrangler's own entry file with Node works the same everywhere.
import { execFileSync, type ExecFileSyncOptions } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const WRANGLER_BIN = join(dirname(require.resolve("wrangler/package.json")), "bin", "wrangler.js");

export function wrangler(args: string[], options: ExecFileSyncOptions & { encoding: BufferEncoding }): string;
export function wrangler(args: string[], options?: ExecFileSyncOptions): Buffer | string;
export function wrangler(args: string[], options: ExecFileSyncOptions = {}) {
  return execFileSync(process.execPath, [WRANGLER_BIN, ...args], options);
}
