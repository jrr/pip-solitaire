// The build timestamp, formatted for a human to read off a screen and quote back. One
// function and no component: the only thing that prints a build stamp is the About
// screen's colophon (`MenuAboutScreen`), which sets it as the line under the build id.
//
// It lives out here rather than in that screen because what it does is a date
// calculation with a wrong answer available — a zero-based month, a local/UTC mix-up,
// an unpaddable field — and those are worth a test file of their own (`BuildStamp_test`)
// rather than a few assertions wedged in beside a screen's markup.

// Zero-pad a date or clock field to two digits (`6` → `"06"`), so the stamp
// reads `2026.07.06 · 06:03` rather than `2026.7.6 · 6:3`.
let pad2 = n => n < 10 ? `0${n->Int.toString}` : n->Int.toString

// Reformat the raw build timestamp — an ISO 8601 string baked in at build time
// (`2026-07-21T11:03:00.000Z`, always UTC — see vite.config.js's `toISOString`)
// — into a fixed-width, unambiguous stamp, in *their own* time zone:
// `2026.07.21 · 06:03` for a viewer six hours behind UTC. It's parsed through
// `Date`, whose `get*` accessors report local time, so the same build reads
// differently depending on where it's opened — no "UTC" suffix, because it's no
// longer UTC. `getMonth` is zero-based, hence the `+ 1`. An unparseable string
// (it shouldn't happen — `getTime` is `NaN`) falls back to itself.
let format = iso => {
  let date = Date.fromString(iso)
  if date->Date.getTime->Float.isNaN {
    iso
  } else {
    let year = date->Date.getFullYear->Int.toString
    let day = `${(date->Date.getMonth + 1)->pad2}.${date->Date.getDate->pad2}`
    let hourMinute = `${date->Date.getHours->pad2}:${date->Date.getMinutes->pad2}`
    `${year}.${day} · ${hourMinute}`
  }
}
