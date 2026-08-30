// The build-version badge, and the timestamp formatting behind it. The badge is one
// line of text; everything with a branch in it is `formatBuildTime`, and every way that
// can go wrong fails quietly — a stamp that has lost its padding, its zone or its date
// still renders as something a reader would take for a build time.
open Vitest
open TestDom

// The widths of the stamp's fields, left to right: `2026.07.21 · 06:03` → [4,2,2,2,2].
let fieldWidths = (stamp: string): array<int> =>
  switch stamp->String.split(" · ") {
  | [date, clock] =>
    Array.concat(
      date->String.split(".")->Array.map(String.length),
      clock->String.split(":")->Array.map(String.length),
    )
  | _ => []
  }

describe("VersionBadge", () => {
  test("shows the version and the build stamp on one line", () => {
    let badge = Html.create(
      VersionBadge.make({version: "abc1234", buildTime: "2026-07-21T11:03:00.000Z"}),
    )
    expect(badge->attr("id"))->toBe(Some("version-badge"))
    expect(badge->text->String.startsWith("vabc1234 · "))->toBe(true)
  })

  test("pads every field, so the stamp is fixed-width whatever the build", () => {
    // Pinned by *shape* — four digits, then four fields of two — because the stamp is
    // read in the local zone, which makes an exact-string assertion a statement about
    // the machine running the test. A single-digit month, day, hour and minute is the
    // case the padding exists for: unpadded it reads `2026.7.6 · 6:3`, which fails the
    // shape in four places at once and leaves the badge's width jumping between builds.
    expect(fieldWidths(VersionBadge.formatBuildTime("2026-07-06T06:03:00.000Z")))->toEqual([
      4,
      2,
      2,
      2,
      2,
    ])
    // …and a build where nothing needed padding formats identically.
    expect(fieldWidths(VersionBadge.formatBuildTime("2026-12-25T22:47:00.000Z")))->toEqual([
      4,
      2,
      2,
      2,
      2,
    ])
  })

  test("reads the stamp in the viewer's own zone, which is why it says no zone", () => {
    // Same instant, two spellings: the badge must render them the same, since what it
    // formats is the moment rather than the text — the ISO string goes through `Date`,
    // whose `get*` accessors are local.
    expect(VersionBadge.formatBuildTime("2026-07-21T11:03:00.000Z"))->toBe(
      VersionBadge.formatBuildTime("2026-07-21T13:03:00.000+02:00"),
    )
    // And no zone is named — the stamp is local, so naming UTC would be a lie.
    expect(VersionBadge.formatBuildTime("2026-07-21T11:03:00.000Z")->String.includes("UTC"))->toBe(
      false,
    )
  })

  test("falls back to the raw string when there's no date to read", () => {
    // `getTime` is NaN here. Shouldn't happen (Vite bakes the value in), but the
    // badge showing "unknown" beats it showing "NaN.NaN.NaN · NaN:NaN".
    expect(VersionBadge.formatBuildTime("unknown"))->toBe("unknown")
    expect(VersionBadge.formatBuildTime(""))->toBe("")
  })
})
