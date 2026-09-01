// The URL parameters the app understands, parsed once at startup. Every one of them
// drives the app into a fixed, shareable position without touching it — which is what
// the screenshot report needs (`?game=freecell&state=midgame`, then shoot it).
//
//   ?game=mini     which game, by id       ?state=midgame  a named `Scenario`
//   ?scene=raster  which scene, by id      ?seed=7         the deal number
//   ?animate=off   skip the deal fly-in    ?raster=svg     the raster scene's rendering
//   ?cascade=pose  freeze the cascade at a fixed frame
//   #g=<blob>      a whole shared game, compressed
//
// Two things are load-bearing here. **`game` and `scene` ask separate questions** — a
// deal link says nothing about which scene to mount, and the raster comparison is no
// game — so `Main` resolves `game` first, it being the more specific claim: naming a
// board answers "which scene" as a side effect, since a game's scene id is its game
// id. And **`state` beats `seed`**: a forced scenario mounts its own fixed deal, so
// there is no shuffle left for a seed to pin.
//
// Why `#g=` rides in the fragment rather than the query is `docs/save-and-share.md`;
// decoding the blob is `ShareLink`'s, and async, so this hands back the raw string.
//
// All plain reads of `window.location`; nothing here mutates the URL.

@val @scope(("window", "location")) external search: string = "search"
@val @scope(("window", "location")) external hash: string = "hash"

// The browser's own parser, so escaping and repeated keys behave as a URL says.
type searchParams
@new external makeSearchParams: string => searchParams = "URLSearchParams"
@send external getParam: (searchParams, string) => Nullable.t<string> = "get"

type t = {
  // Resolved, because this module can see `Game.all`: an unknown id is turned away
  // here rather than travelling on as a string that looks like an answer. `scene`
  // stays raw for the opposite reason — the scene list is built in `Main`.
  game: option<Game.t>,
  scene: option<string>,
  state: option<string>,
  seed: option<int>,
  animate: bool,
  raster: option<RasterScene.rendering>,
  // The cascade demo's mode. `seed` is read twice, deliberately: it is the deal number
  // to a board and the cascade's PRNG seed to that scene, and both are "the number this
  // link replays".
  cascade: option<CascadeScene.mode>,
  shared: option<string>,
}

// A missing *or empty* parameter reads as `None`, so `?scene=` is the same as no
// `scene` at all. Every unrecognised value does likewise: the app opens on its own
// default rather than refusing the link.
let parse = (): t => {
  let params = makeSearchParams(search)
  let read = key =>
    switch params->getParam(key)->Nullable.toOption {
    | Some("") | None => None
    | Some(value) => Some(value)
    }
  let seed = read(ShareLink.dealKey)->Option.flatMap(value => Int.fromString(value))
  let animate = switch read("animate") {
  | Some("off") | Some("no") | Some("false") | Some("0") => false
  | _ => true
  }
  let raster = read("raster")->Option.flatMap(RasterScene.renderingFromString)
  let cascade = read("cascade")->Option.flatMap(CascadeScene.modeFromString)
  // The fragment goes through the same parser once its leading `#` is off, so `#g=…`
  // escapes and repeats by the query's rules — `URLSearchParams` wants bare `k=v`.
  let fragment = makeSearchParams(hash->String.replace("#", ""))
  let shared = switch fragment->getParam(ShareLink.fragmentKey)->Nullable.toOption {
  | Some("") | None => None
  | Some(blob) => Some(blob)
  }
  // An unknown `?game=` falls through to `?scene=` and the launch default, rather than
  // forcing a scene id nothing can mount.
  let game = read(ShareLink.gameKey)->Option.flatMap(Game.byId)
  {game, scene: read("scene"), state: read("state"), seed, animate, raster, cascade, shared}
}
