import { describe, expect, it } from "vitest";
import fixtures from "../../docs/fixtures/normalize.json";
import { cleanText, normalizeAlias, normalizeFidel, normalizeLatin } from "../src/lib/normalize";

// The same fixture runs against ingest/yz/fidel.py (ingest/tests/test_fidel.py): both sides must agree.
type Case = { name: string; in: string; out: string };
const suites: [string, (s: string) => string, Case[]][] = [
  ["normalizeFidel", normalizeFidel, fixtures.fidel],
  ["normalizeLatin", normalizeLatin, fixtures.latin],
  ["cleanText", cleanText, fixtures.clean],
];

for (const [name, fn, cases] of suites) {
  describe(name, () => {
    it.each(cases)("$name", (c) => {
      expect(fn(c.in)).toBe(c.out);
    });
  });
}

describe("normalizeAlias", () => {
  it("routes by script", () => {
    expect(normalizeAlias("ጥላሁን ገሠሠ")).toBe("ጥላሁን ገሰሰ");
    expect(normalizeAlias("Tilahun G.")).toBe("tilahun g.");
    expect(normalizeAlias("Tilahun ጥላሁን")).toBe("Tilahun ጥላሁን"); // any Fidel makes it a Fidel string: Latin is not lowercased
  });

  it("gives homophone spellings of a name the same key", () => {
    expect(normalizeAlias("ሐገሬ")).toBe(normalizeAlias("ኀገሬ"));
    expect(normalizeAlias("ጥላሁን ገሠሠ")).toBe(normalizeAlias("ጥላሁን ገሰሰ"));
  });
});
