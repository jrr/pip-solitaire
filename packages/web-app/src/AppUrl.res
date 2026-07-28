// The URL query parameters the app understands, parsed once at startup. Most are
// aimed at driving the app into a fixed, shareable position without touching it —
// which is exactly what the screenshot report needs (it points a headless browser
// at `?scene=freecell&state=midgame` and shoots the result). The last one, `shake`,
// is the odd one out: a spike switch rather than a positioning knob.
//
//   - `scene` — which scene to mount, by its id (`?scene=freecell`). Overrides the
//     last scene persisted in localStorage, so a link always lands on the named
//     scene regardless of what was last viewed on that device.
//   - `state` — a named starting *scenario* for that scene (`?state=midgame`),
//     resolved against `core`'s `Scenario.forName`. Absent (or unrecognised for
//     the scene) means the ordinary opening deal.
//   - `seed` — the FreeCell deal number to open (`?seed=1`), pinning the otherwise
//     random opening shuffle so a link (and the screenshot report) lands on the same
//     board every time. The future "deal-number" entry point (#98); ignored when a
//     `state` is forced (that mounts the fixed deal itself) or by the fixed-layout
//     demos, which have no seed to vary.
//   - `animate` — whether to play the opening-deal fly-in. On by default; `off`
//     (also `no`/`false`/`0`) drops the cards straight into their resting places, so
//     a shot captures the settled board rather than a frame mid-deal. The same
//     collapse-to-instant the OS "reduce motion" preference already triggers, but
//     addressable from the URL so the report — and a shared link — can ask for it.
//   - `shake` — whether the accelerometer drives the resting cards (`?shake=on`).
//     Off unless asked for: it's an experiment, it prompts for motion permission on
//     iOS, and it leaves the board permanently disarranged. See `CardShake`.
//
// All plain reads of `window.location.search`; nothing here mutates the URL.

@val @scope(("window", "location")) external search: string = "search"

// The browser's own query-string parser, so escaping and repeated keys behave
// exactly as a URL says rather than by hand-rolled splitting.
type searchParams
@new external makeSearchParams: string => searchParams = "URLSearchParams"
@send external getParam: (searchParams, string) => Nullable.t<string> = "get"

type t = {
  scene: option<string>,
  state: option<string>,
  seed: option<int>,
  // Whether to play the opening-deal fly-in; `true` unless the URL asks for `off`.
  animate: bool,
  // Whether to drive the resting cards from the accelerometer (`?shake=on`). Off
  // by default: it's a spike (see `CardShake`), it needs an iOS permission prompt,
  // and it permanently disarranges the board — none of which belongs on a plain
  // visit. Opt-in only, so nothing about the default app changes.
  shake: bool,
}

// Parse the current location's query string. A missing *or empty* parameter reads
// as `None`, so `?scene=` is treated the same as no `scene` at all.
let parse = (): t => {
  let params = makeSearchParams(search)
  let read = key =>
    switch params->getParam(key)->Nullable.toOption {
    | Some("") | None => None
    | Some(value) => Some(value)
    }
  // The deal number to pin, when it parses as an int; a non-numeric `?seed=` is
  // ignored (reads as `None`) rather than crashing the opening deal.
  let seed = read("seed")->Option.flatMap(value => Int.fromString(value))
  // Animate unless the URL explicitly opts out; any other (or absent) value plays
  // the fly-in as before.
  let animate = switch read("animate") {
  | Some("off") | Some("no") | Some("false") | Some("0") => false
  | _ => true
  }
  // The mirror of `animate`: opt *in* rather than out, accepting the same spellings.
  let shake = switch read("shake") {
  | Some("on") | Some("yes") | Some("true") | Some("1") => true
  | _ => false
  }
  {scene: read("scene"), state: read("state"), seed, animate, shake}
}
