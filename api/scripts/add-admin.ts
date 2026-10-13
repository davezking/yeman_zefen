// Seed or update an admin user. Run against the local D1 by default:
//   npx tsx scripts/add-admin.ts you@example.com admin
//   npx tsx scripts/add-admin.ts you@example.com editor -- --remote
//
// It shells out to `wrangler d1 execute`, so it uses the same DB wrangler does.
import { execFileSync } from "node:child_process";
import { ADMIN_ROLES } from "../src/db/schema";

const [email, role, ...rest] = process.argv.slice(2);
const remote = rest.includes("--remote");

if (!email || !role) {
  console.error("Usage: add-admin.ts <email> <admin|editor> [--remote]");
  process.exit(1);
}
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
  console.error(`Not a valid email: ${email}`);
  process.exit(1);
}
if (!(ADMIN_ROLES as readonly string[]).includes(role)) {
  console.error(`Role must be one of: ${ADMIN_ROLES.join(", ")}`);
  process.exit(1);
}

// Values are bound as SQL parameters (?1/?2), so no string interpolation into SQL.
const sql =
  "INSERT INTO admin_users (email, role, created_at) VALUES (?1, ?2, unixepoch() * 1000) " +
  "ON CONFLICT(email) DO UPDATE SET role = excluded.role";

const args = [
  "wrangler",
  "d1",
  "execute",
  "yz-db",
  remote ? "--remote" : "--local",
  "--command",
  sql,
  "--param",
  email,
  "--param",
  role,
];

execFileSync("npx", args, { stdio: "inherit" });
console.log(`${remote ? "[remote]" : "[local]"} ${email} is now ${role}.`);
