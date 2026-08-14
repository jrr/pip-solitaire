// The URL query parameters the app understands, parsed once at startup. Four knobs,
// all aimed at driving the app into a fixed, shareable position without touching
// it — which is exactly what the screenshot report needs (it points a headless
// browser at `?scene=freecell&state=midgame` and shoots the result):
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
//   - `raster` — which of the `raster` scene's three renderings it opens on
//     (`?scene=raster&raster=live|svg|canvas`), resolved by
//     `RasterScene.renderingFromString`. The scene has in-page buttons and the
//     1/2/3 keys too; this is the linkable form of them, so a comparison can be
//     shared, and so the browser suite can shoot each rendering without clicking.
//     An unrecognised name opens the scene's own default.
//
// Plus one parameter that rides in the **fragment** rather than the query:
//
//   - `#g=` — a whole shared game, compressed (`ShareLink`). It's in the fragment
//     because it's far larger than the knobs above and because a fragment is never
//     sent to the server, which is what keeps it clear of the ~8 KB request-line
//     limit servers and CDNs put on a path-and-query. Parsed here with the same
//     `URLSearchParams` the query gets, so `#g=…` escapes and repeats by the same
//     rules; decoding the blob is `ShareLink`'s job, and asynchronous, so all this
//     hands back is the raw string.
//
// All plain reads of `window.location`; nothing here mutates the URL.

@val @scope(("window", "location")) external search: string = "search"
@val @scope(("window", "location")) external hash: string = "hash"

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
  // The `raster` scene's opening rendering; `None` leaves the scene's own default.
  raster: option<RasterScene.rendering>,
  // A shared game's compressed blob, straight off the `#g=` fragment and not yet
  // decoded — turning it into a board is async, so that's `ShareLink`'s job and the
  // caller's timing problem, not this parser's.
  shared: option<string>,
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
  // An unrecognised rendering name reads as `None` — the scene opens on its own
  // default rather than refusing the link.
  let raster = read("raster")->Option.flatMap(RasterScene.renderingFromString)
  // The fragment, parsed with the same machinery as the query once its leading `#`
  // is off — `URLSearchParams` wants bare `k=v` pairs. An empty or absent `#g=`
  // reads as `None`, exactly as an empty query parameter does.
  let fragment = makeSearchParams(hash->String.replace("#", ""))
  let shared = switch fragment->getParam(ShareLink.fragmentKey)->Nullable.toOption {
  | Some("") | None => None
  | Some(blob) => Some(blob)
  }
  {scene: read("scene"), state: read("state"), seed, animate, raster, shared}
}
