// The build-version badge tucked into the corner of the chrome: version and
// build time. (It once carried an "offline-ready" suffix too, but the About
// footer now sits the Update button beside this line, so the suffix was dropped
// to keep the row short — #201.)
//
// A component is just a `props => vnode` function. The JSX transform lowers
// `<VersionBadge .../>` to `Html.jsx(VersionBadge.make, props)` and fills this
// record from the attributes. (The `@jsx.component` sugar that would auto-derive
// `props` isn't usable here — it types `make` as the runtime's `element`, i.e. a
// real DOM node, but on this diffing runtime a view is a `vnode` description — so
// we spell the record out, which is all that sugar expands to anyway.) Layout and
// colors for `#version-badge` live in the stylesheet in index.html; here we build
// only structure and state-dependent text.
type props = {version: string, buildTime: string}

let monthNames = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
]

// Zero-pad a clock field to two digits (`6` → `"06"`), so the time reads
// `06:03` rather than `6:3`.
let pad2 = n => n < 10 ? `0${n->Int.toString}` : n->Int.toString

// Reformat the raw build timestamp — an ISO 8601 string baked in at build time
// (`2026-07-21T11:03:00.000Z`, always UTC — see vite.config.js's `toISOString`)
// — into something a human reads at a glance, in *their own* time zone (#185):
// `Jul 21, 2026 · 06:03` for a viewer six hours behind UTC. It's parsed through
// `Date`, whose `get*` accessors report local time, so the same build reads
// differently depending on where it's opened — no "UTC" suffix, because it's no
// longer UTC. An unparseable string (it shouldn't happen — `getTime` is `NaN`)
// falls back to itself.
let formatBuildTime = iso => {
  let date = Date.fromString(iso)
  if date->Date.getTime->Float.isNaN {
    iso
  } else {
    let monthName = monthNames->Array.get(date->Date.getMonth)->Option.getOr("")
    let day = date->Date.getDate->Int.toString
    let year = date->Date.getFullYear->Int.toString
    let hourMinute = `${date->Date.getHours->pad2}:${date->Date.getMinutes->pad2}`
    `${monthName} ${day}, ${year} · ${hourMinute}`
  }
}

let make = ({version, buildTime}) => {
  let built = formatBuildTime(buildTime)
  <div id="version-badge"> {Html.string(`v${version} · ${built}`)} </div>
}
