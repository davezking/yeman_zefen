import { describe, expect, it } from "vitest";
import wranglerToml from "../wrangler.toml?raw";
import devServices from "../../app/android/app/src/dev/google-services.json?raw";
import prodServices from "../../app/android/app/src/prod/google-services.json?raw";

// The Worker accepts a player's token only for its FIREBASE_PROJECT_ID, so each environment must name the
// Firebase project of the app flavor that talks to it. A mismatch makes every sign-in a 401 (docs/ops.md).
const projectOf = (services: string) => (JSON.parse(services) as { project_info: { project_id: string } }).project_info.project_id;

/** FIREBASE_PROJECT_ID of one wrangler.toml table, e.g. "[env.prod.vars]" ("[vars]" for the top level). */
function firebaseProjectIn(table: string): string | undefined {
  const start = wranglerToml.indexOf(`\n${table}\n`);
  if (start < 0) return undefined;
  const rest = wranglerToml.slice(start + table.length + 2);
  const end = rest.search(/^\[/m);
  return /^FIREBASE_PROJECT_ID = "([^"]+)"/m.exec(end < 0 ? rest : rest.slice(0, end))?.[1];
}

describe("FIREBASE_PROJECT_ID", () => {
  it("names the dev Firebase project for local dev and staging, and the prod project for prod", () => {
    expect(firebaseProjectIn("[vars]")).toBe(projectOf(devServices));
    expect(firebaseProjectIn("[env.staging.vars]")).toBe(projectOf(devServices));
    expect(firebaseProjectIn("[env.prod.vars]")).toBe(projectOf(prodServices));
  });

  it("reads the project ids at all", () => {
    expect(projectOf(devServices)).not.toBe(projectOf(prodServices));
    expect(firebaseProjectIn("[env.prod.vars]")).toBeTruthy();
  });
});
