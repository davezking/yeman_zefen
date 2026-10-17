import { env } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { MAX_REPORT_DAYS, csvCell, reportFilename, royaltyCsv, type RoyaltyRow } from "../src/lib/royaltyReport";
import { adminWithQueryCount, api, installTestJwks, makeArtist, makeTrack, rawRequest, removeTestJwks, resetCatalog, seedAdmins } from "./helpers";

let ids: { a: number; b: number; c: number };

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
  await resetCatalog();
  const selam = await makeArtist("ሰላም", "Selam");
  const nameless = await makeArtist("አርቲስት");
  const a = await makeTrack(selam.id, { titleAm: "ሰላም ሰላም", titleLatin: "Selam Selam", album: "First, Album", releaseYear: 1975 });
  const b = await makeTrack(selam.id, { titleAm: "እናት", titleLatin: 'The "Mother" song', album: null, releaseYear: null });
  const c = await makeTrack(nameless.id, { titleAm: null, titleLatin: "=HYPERLINK(1)", album: "Live", releaseYear: 1990 });
  ids = { a: a.id, b: b.id, c: c.id };
});
afterAll(removeTestJwks);

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM royalty_daily").run();
  const rows: [string, number, number][] = [
    ["2026-09-30", ids.a, 100], // before the range
    ["2026-10-01", ids.a, 5],
    ["2026-10-01", ids.b, 7],
    ["2026-10-02", ids.a, 3],
    ["2026-10-02", ids.c, 11],
    ["2026-10-03", ids.b, 2],
    ["2026-10-04", ids.a, 50], // after the range
  ];
  await env.DB.batch(
    rows.map(([d, t, p]) => env.DB.prepare("INSERT INTO royalty_daily (date, track_id, plays) VALUES (?1, ?2, ?3)").bind(d, t, p)),
  );
});

const url = (q: Record<string, string>) => `/admin/reports/royalty?${new URLSearchParams(q)}`;
const RANGE = { from: "2026-10-01", to: "2026-10-03" };

describe("GET /admin/reports/royalty (json)", () => {
  it("sums plays per track over the range, both days included, most played first", async () => {
    const res = await api(url(RANGE));
    expect(res.status).toBe(200);
    const body = (await res.json()) as { from: string; to: string; totalPlays: number; rows: RoyaltyRow[] };

    expect(body.rows.map((r) => [r.trackId, r.plays])).toEqual([
      [ids.c, 11],
      [ids.b, 9],
      [ids.a, 8],
    ]);
    expect([body.from, body.to]).toEqual([RANGE.from, RANGE.to]);
  });

  it("joins the titles, artist, album and year", async () => {
    const body = (await (await api(url(RANGE))).json()) as { rows: RoyaltyRow[] };
    const a = body.rows.find((r) => r.trackId === ids.a)!;

    expect(a).toMatchObject({
      titleAm: "ሰላም ሰላም",
      titleLatin: "Selam Selam",
      artistAm: "ሰላም",
      artistLatin: "Selam",
      album: "First, Album",
      releaseYear: 1975,
    });
  });

  it("the total equals the sum of royalty_daily for the range", async () => {
    const body = (await (await api(url(RANGE))).json()) as { totalPlays: number };
    const raw = await env.DB.prepare("SELECT SUM(plays) AS n FROM royalty_daily WHERE date >= ?1 AND date <= ?2")
      .bind(RANGE.from, RANGE.to)
      .first<{ n: number }>();

    expect(body.totalPlays).toBe(raw!.n);
    expect(body.totalPlays).toBe(28);
  });

  it("a range with no plays is an empty report with a total of 0", async () => {
    const body = (await (await api(url({ from: "2026-01-01", to: "2026-01-31" }))).json()) as { rows: unknown[]; totalPlays: number };

    expect(body.rows).toEqual([]);
    expect(body.totalPlays).toBe(0);
  });

  it("says when the range includes today, which is not rolled up yet", async () => {
    const today = new Date().toISOString().slice(0, 10);
    const past = (await (await api(url(RANGE))).json()) as { includesToday: boolean };
    const incl = (await (await api(url({ from: RANGE.from, to: today }))).json()) as { includesToday: boolean };

    expect(past.includesToday).toBe(false);
    expect(incl.includesToday).toBe(true);
  });

  it("is one D1 query for the report (plus the admin check), whatever the range holds", async () => {
    const { response, queries } = await adminWithQueryCount(url(RANGE));

    expect(response.status).toBe(200);
    expect(queries).toBe(2);
  });
});

describe("GET /admin/reports/royalty (csv)", () => {
  async function csv(q: Record<string, string> = RANGE) {
    const res = await api(url({ ...q, format: "csv" }));
    const bytes = new Uint8Array(await res.arrayBuffer());
    return { res, bytes, text: new TextDecoder("utf-8", { fatal: false, ignoreBOM: true }).decode(bytes) };
  }

  it("is UTF-8 with a byte order mark, so Excel reads Fidel", async () => {
    const { res, bytes, text } = await csv();

    expect(res.headers.get("content-type")).toBe("text/csv; charset=utf-8");
    expect([...bytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    expect(text).toContain("ሰላም ሰላም");
    expect(text).toContain("እናት");
  });

  it("names the file after the range", async () => {
    const { res } = await csv();

    expect(res.headers.get("content-disposition")).toBe('attachment; filename="royalty-report-2026-10-01_to_2026-10-03.csv"');
  });

  it("has a header row, one row per track, and a final total row", async () => {
    const { text } = await csv();
    const lines = text.replace("﻿", "").trimEnd().split("\r\n");

    expect(lines[0]).toBe("Track ID,Title (Amharic),Title (Latin),Artist (Amharic),Artist (Latin),Album,Release year,Plays");
    expect(lines).toHaveLength(1 + 3 + 1);
    expect(lines.at(-1)).toBe("Total,,,,,,,28");
  });

  it("quotes commas and quotes, and defuses a title that would run as a formula", async () => {
    const { text } = await csv();

    expect(text).toContain('"First, Album"');
    expect(text).toContain('"The ""Mother"" song"');
    expect(text).toContain("'=HYPERLINK(1)");
    expect(text).not.toMatch(/,=HYPERLINK/);
  });

  it("an empty range is the header and a total of 0", async () => {
    const { text } = await csv({ from: "2026-01-01", to: "2026-01-31" });

    expect(text.replace("﻿", "").trimEnd().split("\r\n")).toHaveLength(2);
    expect(text).toContain("Total,,,,,,,0");
  });
});

describe("validation and access", () => {
  const bad: Record<string, Record<string, string>> = {
    "no range": {},
    "no to": { from: "2026-10-01" },
    "not a date": { from: "yesterday", to: "2026-10-03" },
    "not a real day": { from: "2026-02-30", to: "2026-03-05" },
    "to before from": { from: "2026-10-03", to: "2026-10-01" },
    "unknown format": { ...RANGE, format: "xml" },
  };
  for (const [name, q] of Object.entries(bad)) {
    it(`${name} is a 400`, async () => {
      const res = await api(url(q));

      expect(res.status).toBe(400);
      expect(((await res.json()) as { error: { code: string } }).error.code).toBe("validation_error");
    });
  }

  it(`a range of ${MAX_REPORT_DAYS} days is allowed and one day more is not`, async () => {
    expect((await api(url({ from: "2025-10-01", to: "2026-10-01" }))).status).toBe(200); // 366 days
    expect((await api(url({ from: "2025-09-30", to: "2026-10-01" }))).status).toBe(400); // 367 days
  });

  it("is for admins: an editor gets 403", async () => {
    const res = await api(url(RANGE), { as: "editor" });

    expect(res.status).toBe(403);
  });

  it("needs a sign-in", async () => {
    const res = await rawRequest(url(RANGE));

    expect(res.status).toBe(401);
  });
});

describe("csv helpers", () => {
  it("quotes only what needs it", () => {
    expect(csvCell("plain")).toBe("plain");
    expect(csvCell("a,b")).toBe('"a,b"');
    expect(csvCell("two\nlines")).toBe('"two\nlines"');
    expect(csvCell(null)).toBe("");
    expect(csvCell(12)).toBe("12");
  });

  it("defuses formula starts in text, never in numbers", () => {
    for (const s of ["=1+1", "+1", "-1", "@SUM(A1)"]) expect(csvCell(s)).toBe(`'${s}`);
    expect(csvCell(-5)).toBe("-5");
  });

  it("names the file with the range", () => {
    expect(reportFilename("2026-07-01", "2026-09-30")).toBe("royalty-report-2026-07-01_to_2026-09-30.csv");
  });

  it("builds a report for no rows", () => {
    expect(royaltyCsv([])).toBe(
      "﻿Track ID,Title (Amharic),Title (Latin),Artist (Amharic),Artist (Latin),Album,Release year,Plays\r\nTotal,,,,,,,0\r\n",
    );
  });
});
