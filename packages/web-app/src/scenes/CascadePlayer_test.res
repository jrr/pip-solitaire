// The cascade's machinery where jsdom can reach it: the policies both callers inherit —
// which settings restart a run and which one in flight simply takes, where cards launch
// from, what a resize costs. The physics is `Cascade_test`'s and the pixels are
// `browser-tests/cascade.spec.mjs`'s.
//
// The stubs are `TrailScene_test`'s: jsdom answers the way an engine with no 2D
// implementation does, and `fetch` rejects rather than leaving the runner on a socket.
%%raw(`
  if (globalThis.HTMLCanvasElement) {
    globalThis.HTMLCanvasElement.prototype.getContext = () => null
  }
  globalThis.fetch = () => Promise.reject(new Error("no network in jsdom"))
`)

open Vitest

// As the window delivers it, so these check the wiring and the policy together.
let fireResize: unit => unit = %raw(`() => globalThis.dispatchEvent(new Event("resize"))`)

// A sheet with no rasterizer under it: only the two fields a blit has to agree on matter.
let sheet = (~cssWidth, ~pixelRatio=CardRaster.displayPixelRatio()): CardRaster.t => {
  cssWidth,
  pixelRatio,
  elapsedMs: 0.,
  sprites: Dict.make(),
}

// A sheet already in hand, so paths that would wait on a rasterizer run here and now.
let ready = (~options=CascadePlayer.defaults, ~intent=CascadePlayer.Live) => {
  let player = CascadePlayer.attach(~canvas=Canvas.make(), ~options)
  player.sprites = Some(sheet(~cssWidth=options.cardWidth))
  player.intent = intent
  player
}

// Detach before a test ends, or an attached player hears the *next* test's resize.
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
      // The seam #228 arrives through, in card-widths like everything the motion sees.
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

    // A ratio that moved under it — a browser zoom — is the same failure, and the one
    // that shows as nothing at all: softer cards, and no error.
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
    // What you tune is the cascade in front of you, not the next one.
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
    // Dropped rather than scaled: scaling is the resample this approach exists to avoid.
    after(player, () => expect(CascadePlayer.status(player).sprites)->toEqual(None))
  })

  test("moved while the deck is still rasterizing, it waits rather than paying twice", () => {
    let player = CascadePlayer.attach(~canvas=Canvas.make())
    CascadePlayer.start(player)
    let inFlight = player.wanted
    // A different cascade, but the same 52 bitmaps.
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
    // A `clear` takes the canvas and leaves the listener holding a scene that is gone.
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
    // `isDone`, seen through the phase a caller reads.
    let cards: array<Deck.card> = [{suit: Deck.Spades, rank: Deck.Ace}]
    let player = ready(~options={...CascadePlayer.defaults, cards: Some(cards)})
    let stage: Cascade.stage = {width: 4., height: 6., seats: [(2., 0.)]}
    for _ in 1 to 200 {
      player.run = Cascade.step(player.run, ~knobs=player.options.knobs, ~stage, ~dt=1. /. 120.)
    }
    after(player, () => expect(CascadePlayer.status(player).phase)->toEqual(CascadePlayer.Settled))
  })
})
