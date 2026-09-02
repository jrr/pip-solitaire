// The cascade's machinery where jsdom can reach it: the decisions, not the pixels.
//
// The physics is `Cascade_test`'s and the drawing is `browser-tests/cascade.spec.mjs`'s,
// which has an engine and a buffer to read back. What is left is what *both* callers of
// the player inherit whether or not either ever draws — which settings restart a cascade
// and which a run in flight simply takes, where a card launches from when the seats are
// the caller's own rather than a demo's spread, and what a resize costs a run. Each of
// those is a policy the victory overlay gets by asking for one and passing an `options`,
// and the way it would otherwise arrive is as a second, slightly different copy.
//
// The stubs are `TrailScene_test`'s, for its reasons: jsdom is made to answer the way an
// engine with no 2D implementation does, and `fetch` rejects immediately rather than
// leaving the runner waiting on a socket that isn't there.
%%raw(`
  if (globalThis.HTMLCanvasElement) {
    globalThis.HTMLCanvasElement.prototype.getContext = () => null
  }
  globalThis.fetch = () => Promise.reject(new Error("no network in jsdom"))
`)

open Vitest

// The resize the player listens for, as the window actually delivers it — so what these
// check is the wiring and the policy together, and `detach` can be checked at all.
let fireResize: unit => unit = %raw(`() => globalThis.dispatchEvent(new Event("resize"))`)

// A sheet that is what it says it is, with no rasterizer under it. Only the two fields a
// blit has to agree on are load-bearing here; nothing draws in jsdom.
let sheet = (~cssWidth, ~pixelRatio=CardRaster.displayPixelRatio()): CardRaster.t => {
  cssWidth,
  pixelRatio,
  elapsedMs: 0.,
  sprites: Dict.make(),
}

// A player with a sheet already in hand and something asked of it, so the paths that
// would otherwise wait on a rasterizer run here and now.
let ready = (~options=CascadePlayer.defaults, ~intent=CascadePlayer.Live) => {
  let player = CascadePlayer.attach(~canvas=Canvas.make(), ~options)
  player.sprites = Some(sheet(~cssWidth=options.cardWidth))
  player.intent = intent
  player
}

// Every player here is detached before its test ends: an attached one keeps a `window`
// listener, so it would hear the *next* test's resize and start a frame loop inside it.
let after = (player, check) => {
  check()
  CascadePlayer.detach(player)
}

describe("where a cascade launches from", () => {
  test("spreads its seats across the stage when the caller has none of its own", () => {
    let player = ready(~options={...CascadePlayer.defaults, launchpad: CascadePlayer.Spread(4)})
    after(player, () => expect(Array.length(CascadePlayer.stageOf(player).seats))->toBe(4))
  })

  test(
    "takes the caller's own seats as given — a board's foundations are where it put them",
    () => {
      // The seam #228 arrives through. Seats are in card-widths, like everything else the
      // motion sees, so a board hands over its foundations measured the way it draws them.
      let seats = [(1.5, 0.4), (3.5, 0.4)]
      let player = ready(~options={...CascadePlayer.defaults, launchpad: CascadePlayer.At(seats)})
      after(player, () => expect(CascadePlayer.stageOf(player).seats)->toEqual(seats))
    },
  )

  test("falls the cards the caller hands over, in the order it hands them over", () => {
    let cards: array<Deck.card> = [
      {suit: Deck.Spades, rank: Deck.King},
      {suit: Deck.Hearts, rank: Deck.Two},
    ]
    let player = ready(~options={...CascadePlayer.defaults, cards: Some(cards)})
    after(player, () => expect(player.run.cards)->toEqual(cards))
  })
})

describe("the sprite sheet in hand", () => {
  test("serves a blit only if it was built for this card size, at this ratio", () => {
    let player = ready()
    expect(CascadePlayer.spritesStale(player))->toBe(false)

    player.sprites = Some(sheet(~cssWidth=140.))
    expect(CascadePlayer.spritesStale(player))->toBe(true)

    // A ratio that moved under it — a browser zoom — is the same failure, and it is the
    // one that shows as nothing at all: the cards come out softer by the ratio between
    // the two, and no error says so.
    player.sprites = Some(
      sheet(
        ~cssWidth=CascadePlayer.defaults.cardWidth,
        ~pixelRatio=CardRaster.displayPixelRatio() +. 0.5,
      ),
    )
    after(player, () => expect(CascadePlayer.spritesStale(player))->toBe(true))
  })
})

describe("new settings, handed over mid-flight", () => {
  // One step, so the run has got somewhere and a restart is visible as one.
  let underway = (player: CascadePlayer.t) =>
    player.run = Cascade.step(
      player.run,
      ~knobs=player.options.knobs,
      ~stage=CascadePlayer.stageOf(player),
      ~dt=0.05,
    )

  test("a live run takes a knob on its next step rather than starting over", () => {
    // The whole reason a slider is worth having: what you are tuning is the cascade in
    // front of you, not the next one.
    let player = ready()
    underway(player)
    CascadePlayer.retune(player, {...player.options, knobs: {...Cascade.defaults, gravity: 40.}})
    after(
      player,
      () => {
        expect(player.run.launched)->toBe(1)
        expect(player.options.knobs.gravity)->toBe(40.)
      },
    )
  })

  test("but a new seed is a different cascade, so it starts one", () => {
    let player = ready()
    underway(player)
    expect(player.run.launched)->toBe(1)
    CascadePlayer.retune(player, {...player.options, seed: 9})
    after(player, () => expect(player.run.launched)->toBe(0))
  })

  test("and a new card size is a new sheet, which the run waits for", () => {
    let player = ready()
    CascadePlayer.retune(player, {...player.options, cardWidth: 140.})
    // The sheet in hand was cut at 90px, so it is dropped rather than scaled — the
    // resample this whole approach exists to avoid.
    after(player, () => expect(CascadePlayer.status(player).sprites)->toEqual(None))
  })

  test("moved while the deck is still rasterizing, it waits rather than paying twice", () => {
    let player = CascadePlayer.attach(~canvas=Canvas.make())
    CascadePlayer.start(player)
    let inFlight = player.wanted
    // A different cascade, but the same 52 bitmaps: the build already running is the one
    // this is waiting for.
    CascadePlayer.retune(player, {...player.options, seed: 5})
    expect(player.wanted)->toBe(inFlight)
    // A different card size is not, and that one it does pay for.
    CascadePlayer.retune(player, {...player.options, cardWidth: 140.})
    after(player, () => expect(player.wanted)->toBe(inFlight + 1))
  })
})

describe("a resize", () => {
  test("ends a live run, because the store's wipe takes a trail nothing can recompute", () => {
    let player = ready()
    fireResize()
    after(
      player,
      () => expect(CascadePlayer.status(player).phase)->toEqual(CascadePlayer.Interrupted),
    )
  })

  test("costs a still nothing at all, so it is simply drawn again", () => {
    let player = ready(~intent=CascadePlayer.Pose(1.))
    fireResize()
    after(player, () => expect(CascadePlayer.status(player).phase)->toEqual(CascadePlayer.Posed))
  })

  test("is not heard by a player that has been detached", () => {
    // What a caller's own teardown can't reach: the container's `clear` takes the canvas
    // and leaves the `window` listener holding a scene that is gone.
    let heard = ref(0)
    let player = CascadePlayer.attach(
      ~canvas=Canvas.make(),
      ~onChange=_ => heard := heard.contents + 1,
    )
    fireResize()
    let before = heard.contents
    expect(before > 0)->toBe(true)
    CascadePlayer.detach(player)
    fireResize()
    expect(heard.contents)->toBe(before)
  })
})

describe("what the player says it is doing", () => {
  test("has nothing to draw until a sheet lands, whatever has been asked of it", () => {
    let player = CascadePlayer.attach(~canvas=Canvas.make())
    after(player, () => expect(CascadePlayer.status(player).phase)->toEqual(CascadePlayer.Building))
  })

  test("is settled once the last card has left the stage", () => {
    // A stage a card leaves at once, and two cards to leave it: what `isDone` is, seen
    // through the phase a caller reads.
    let cards: array<Deck.card> = [{suit: Deck.Spades, rank: Deck.Ace}]
    let player = ready(~options={...CascadePlayer.defaults, cards: Some(cards)})
    let stage: Cascade.stage = {width: 4., height: 6., seats: [(2., 0.)]}
    for _ in 1 to 200 {
      player.run = Cascade.step(player.run, ~knobs=player.options.knobs, ~stage, ~dt=1. /. 120.)
    }
    after(player, () => expect(CascadePlayer.status(player).phase)->toEqual(CascadePlayer.Settled))
  })
})
