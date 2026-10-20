import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import app from "../src/index";

const page = (email?: string) => app.fetch(new Request("https://api.test/account-deletion"), { ...env, PRIVACY_CONTACT_EMAIL: email });

describe("GET /account-deletion", () => {
  it("is not served until the contact address is set (wrangler.toml leaves it empty)", async () => {
    const res = await exports.default.fetch(new Request("https://api.test/account-deletion"));
    expect(res.status).toBe(503);
    expect(await res.json()).toMatchObject({ error: { code: "not_configured" } });
    expect((await page("   ")).status).toBe(503);
  });

  it("serves the steps, in English and Amharic, publicly and cached for an hour", async () => {
    const res = await page("privacy@yemanzefen.test");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("cache-control")).toBe("public, max-age=3600");
    expect(res.headers.get("content-security-policy")).toContain("default-src 'none'");
    const html = await res.text();
    expect(html).toContain("Settings › Account › Delete account");
    expect(html).toContain('href="mailto:privacy@yemanzefen.test?subject=Delete%20my%20Yeman%20Zefen%20account"');
    expect(html).toContain('<section lang="en">');
    expect(html).toContain('<section lang="am">');
  });

  it("escapes the address", async () => {
    const html = await (await page('a"<b>@x.test')).text();
    expect(html).not.toContain("<b>");
    expect(html).toContain("a&quot;&lt;b&gt;@x.test");
  });
});
