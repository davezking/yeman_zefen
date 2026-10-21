// Seed or update an admin user. Run against the local D1 by default:
//   npx tsx scripts/add-admin.ts you@example.com admin
//   npx tsx scripts/add-admin.ts you@example.com editor --remote --env prod
//
// With ADMIN_LOGIN=firebase, use the Google account the admin signs in with (docs/ops.md).
// It shells out to `wrangler d1 execute`, so it uses the same DB wrangler does.
import { execFileSync } from "node:child_process";
import { ADMIN_ROLES } from "../src/db/schema";

const [email, role, ...rest] = process.argv.slice(2);
const remote = rest.includes("--remote");
const envIndex = rest.indexOf("--env");
const env = envIndex >= 0 ? rest[envIndex + 1] : undefined;

if (!email || !role) {
  console.error("Usage: add-admin.ts <email> <admin|editor> [--remote --env prod]");
  process.exit(1);
}
if (!/^[^@\s'"\;]+@[^@\s'"\;]+\.[^@\s'"\;]+$/.test(email)) {
  console.error(`Not a valid email: ${email}`);
  process.exit(1);
}
if (!(ADMIN_ROLES as readonly string[]).includes(role)) {
  console.error(`Role must be one of: ${ADMIN_ROLES.join(", ")}`);
  process.exit(1);
}
// Without --env, wrangler uses the top-level database in wrangler.toml, whose id is a placeholder.
if (remote && !env) {
  console.error("--remote needs the environment too: add --env prod (or --env staging).");
  process.exit(1);
}

// `wrangler d1 execute` cannot bind parameters, so the values go into the SQL as literals. Both are checked
// above: the role is one of ADMIN_ROLES and the email cannot contain a quote, a backslash or a semicolon.
// Quotes are doubled anyway, so a looser check later cannot open the string.
const literal = (s: string) => `'${s.replace(/'/g, "''")}'`;
const sql =
  `INSERT INTO admin_users (email, role, created_at) VALUES (${literal(email)}, ${literal(role)}, unixepoch() * 1000) ` +
  "ON CONFLICT(email) DO UPDATE SET role = excluded.role";

const args = ["wrangler", "d1", "execute", "yz-db", remote ? "--remote" : "--local", ...(env ? ["--env", env] : []), "--command", sql];

execFileSync("npx", args, { stdio: "inherit" });
console.log(`${remote ? `[remote, ${env}]` : "[local]"} ${email} is now ${role}.`);
