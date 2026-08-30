// The build-version badge, and the timestamp formatting behind it.
//
// The badge itself is one line of text, but `formatBuildTime` has three behaviours
// worth pinning, all of which fail quietly:
//
// 1. **Every field is zero-padded.** Without `pad2` a build stamped at 06:03 on the
//    6th reads `2026.7.6 · 6:3` — still parseable by a human, but not
//    fixed-width, so the badge's width jumps around between builds and two stamps
//    can't be compared down a column.
// 2. **It reports the viewer's own time zone**, not UTC: the ISO string is
//    parsed through `Date`, whose `get*` accessors are local. That's the reason the
//    stamp carries no "UTC" suffix.
// 3. **An unparseable stamp falls back to itself.** It shouldn't happen — the value
//    is baked in by Vite — but a build that ran without one must show *something*
//    rather than "NaN.NaN.NaN".
//
// The zone makes an exact-string assertion a statement about the machine running
// the test, so the padding is pinned by *shape*: four digits, then four fields of
// two. That is precisely what `pad2` owes, and `2026.7.6 · 6:3` fails it in four
// places at once.
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
    // A single-digit month, day, hour and minute — the case the padding exists for.
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
    // Same instant, two spellings: the badge must render them the same, since what
    // it formats is the moment rather than the text.
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
