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
      // The seam a board arrives through, in card-widths like everything the motion
      // sees: its foundations are wherever it put them.
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

  test("hands each card back as it leaves, in launch order", () => {
    // What a board empties its foundations off: the node a sprite has taken over
    // from is hidden on this call. It can't ride on `onChange`, which is a half-second
    // heartbeat — a card left on the table for half a second after its copy has flown
    // off it is a card in two places.
    let cards: array<Deck.card> = [
      {suit: Deck.Spades, rank: Deck.King},
      {suit: Deck.Hearts, rank: Deck.Queen},
      {suit: Deck.Clubs, rank: Deck.Jack},
    ]
    let launched = []
    let player = CascadePlayer.attach(
      ~canvas=Canvas.make(),
      ~options={...CascadePlayer.defaults, cards: Some(cards)},
      ~onLaunch=card => launched->Array.push(card),
    )
    player.sprites = Some(sheet(~cssWidth=CascadePlayer.defaults.cardWidth))
    // A pose rather than a live run: the same `advance`, off a fixed number of steps
    // instead of a clock, so the count is the launch interval's rather than the
    // runner's. Two seconds is the first card plus two more at 750ms apiece.
    CascadePlayer.pose(player, ~seconds=2.)
    after(player, () => expect(launched)->toEqual(cards))
  })

  test("puts each one out before it throws it, and never the other way round", () => {
    // The board shows one card per seat: `onReady` is its cue to put a card out and
    // `onLaunch` its cue to take it away, so a card announced the wrong way round would
    // be shown after it had already gone — and stay on the table for the whole run.
    let cards: array<Deck.card> = [
      {suit: Deck.Spades, rank: Deck.King},
      {suit: Deck.Hearts, rank: Deck.Queen},
    ]
    let log = []
    let player = CascadePlayer.attach(
      ~canvas=Canvas.make(),
      ~options={...CascadePlayer.defaults, cards: Some(cards), launchpad: CascadePlayer.Spread(2)},
      ~onLaunch=card => log->Array.push(("gone", card)),
      ~onReady=card => log->Array.push(("out", card)),
    )
    player.sprites = Some(sheet(~cssWidth=CascadePlayer.defaults.cardWidth))
    CascadePlayer.pose(player, ~seconds=2.)
    after(
      player,
      () =>
        expect(log)->toEqual([
          // Both seats' tops are out from the first step, which is a board's opening piles.
          ("out", cards->Array.getUnsafe(0)),
          ("out", cards->Array.getUnsafe(1)),
          ("gone", cards->Array.getUnsafe(0)),
          ("gone", cards->Array.getUnsafe(1)),
        ]),
    )
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

describe("the fade behind the cards", () => {
  test("is the share of a second the caller asked for, whatever it is paid in", () => {
    // Two half-seconds have to leave the surface where one second does, or the fade
    // would be a different trail at every stamp interval.
    expect(CascadePlayer.fadeShare(~rate=0.5, ~ms=1000.))->toBeCloseToWithin(0.5, 6)
    let half = CascadePlayer.fadeShare(~rate=0.5, ~ms=500.)
    expect(1. -. (1. -. half) *. (1. -. half))->toBeCloseToWithin(0.5, 6)
  })

  test("is off for `Forever`, which is the trail that keeps everything", () => {
    // No case of its own anywhere below this: an infinite persistence is a rate of zero,
    // and a rate of zero takes nothing off.
    let seconds = CascadePlayer.persistenceSeconds(CascadePlayer.Forever, ~launchMs=750., ~cards=52)
    expect(seconds)->toBe(infinity)
    expect(CascadePlayer.fadeRate(~seconds))->toBe(0.)
    expect(CascadePlayer.fadeShare(~rate=0., ~ms=1000.))->toBe(0.)
    expect(CascadePlayer.fadePayment(~rate=0., ~coin=0.1, ~stampMs=16.))->toBe(infinity)
  })

  test("comes due on the stretch whose share is one coin", () => {
    // The number a coin is read by: one full-surface fill this often is the whole of
    // what the fade costs to run.
    let rate = CascadePlayer.fadeRate(~seconds=6.75)
    let every = CascadePlayer.fadePayment(~rate, ~coin=0.1, ~stampMs=16.)
    expect(Math.round(every *. 1000.))->toBe(154.)
    // A bigger bite is a rarer fill…
    expect(CascadePlayer.fadePayment(~rate, ~coin=0.3, ~stampMs=16.) > every)->toBe(true)
    // …and one smaller than a stamp's worth is still only paid at a stamp, which is the
    // only moment there is to pay it at.
    expect(CascadePlayer.fadePayment(~rate, ~coin=0.001, ~stampMs=16.))->toBe(0.016)
  })

  test("is saved up until it is worth a coin, instead of being spent on a rounding error", () => {
    // At the default trail interval half a second's fade is a hundredth of a stamp,
    // which an eight-bit alpha rounds straight back to where it was — so the player
    // holds the debt and spends it once it is worth a coin (see `Canvas.dim`).
    let player = ready()
    let paidAfter = ref(0)
    for stamp in 1 to 40 {
      let owed = player.fadeOwedMs
      CascadePlayer.dim(player, ~seats=4)
      if player.fadeOwedMs < owed && paidAfter.contents == 0 {
        paidAfter := stamp
      }
    }
    // 154ms is what a tenth costs at nine cards of persistence, which is ten 16ms stamps.
    expect(paidAfter.contents)->toBe(10)
    after(player, () => expect(player.fadeOwedMs < 160.)->toBe(true))
  })

  test("takes its coin from the options, so a debug slider can move it on a live board", () => {
    // A bigger bite is a longer wait between fills, which is what the cost is read off:
    // a fifth takes 322ms of simulated time to owe where a tenth takes 152.
    let player = ready(
      ~options={
        ...CascadePlayer.defaults,
        fade: {...CascadePlayer.defaultFade, step: CascadePlayer.Coin(0.2)},
      },
    )
    let paidAfter = ref(0)
    for stamp in 1 to 60 {
      let owed = player.fadeOwedMs
      CascadePlayer.dim(player, ~seats=4)
      if player.fadeOwedMs < owed && paidAfter.contents == 0 {
        paidAfter := stamp
      }
    }
    after(player, () => expect(paidAfter.contents)->toBe(21))
  })

  test("is one length of time whichever of the four units says it", () => {
    // The units are a way of writing the setting down, not four settings: at the default
    // launch interval nine cards, 6.75 seconds and a 52nd-of-a-run-times-nine are the
    // same trail, and only a run of another shape tells them apart.
    let at = persistence => CascadePlayer.persistenceSeconds(persistence, ~launchMs=750., ~cards=52)
    expect(at(CascadePlayer.Cards(9.)))->toBe(6.75)
    expect(at(CascadePlayer.Seconds(6.75)))->toBe(6.75)
    expect(at(CascadePlayer.Fraction(9. /. 52.)))->toBeCloseToWithin(6.75, 6)
  })

  test("and the units part company on a deck of another size, which is the point", () => {
    // A short deck's victory: the same nine cards of trail, which is the same picture on
    // the stage, where the same *fraction* would be a trail four times shorter.
    let short = persistence =>
      CascadePlayer.persistenceSeconds(persistence, ~launchMs=750., ~cards=13)
    expect(short(CascadePlayer.Cards(9.)))->toBe(6.75)
    expect(short(CascadePlayer.Fraction(9. /. 52.)))->toBeCloseToWithin(6.75 /. 4., 6)
  })

  test("says the same length in another unit when the unit changes under it", () => {
    // What a unit picker does. Nine cards *is* 6.75 seconds, so switching which unit it
    // is written in must leave the animation exactly where it was.
    let converted = CascadePlayer.sameIn(
      CascadePlayer.Cards(9.),
      ~like=CascadePlayer.Seconds(0.),
      ~launchMs=750.,
      ~cards=52,
    )
    expect(converted)->toEqual(CascadePlayer.Seconds(6.75))

    // `Forever` has no length to carry over, so leaving it lands on the default in the
    // unit asked for rather than on an infinity no slider could show.
    let leaving = CascadePlayer.sameIn(
      CascadePlayer.Forever,
      ~like=CascadePlayer.Cards(0.),
      ~launchMs=750.,
      ~cards=52,
    )
    expect(leaving)->toEqual(CascadePlayer.Cards(9.))
  })

  test("takes a persistence in cards from the run it is in, not from the deck it isn't", () => {
    // The conversion reads the cards the *player* was given, so a board emptying four
    // foundations of a short deck fades by its own run's length.
    let cards: array<Deck.card> = [
      {suit: Deck.Spades, rank: Deck.Ace},
      {suit: Deck.Hearts, rank: Deck.Two},
    ]
    let player = ready(~options={...CascadePlayer.defaults, cards: Some(cards)})
    after(
      player,
      () =>
        expect(
          CascadePlayer.persistenceSeconds(
            CascadePlayer.Fraction(0.5),
            ~launchMs=player.options.knobs.launchMs,
            ~cards=Array.length(player.run.cards),
          ),
        )->toBe(0.75),
    )
  })

  test("counts a layer as one time round the seats, which is a rank off the foundations", () => {
    // `Cascade` deals its seats in order and a board's piles come off a slot at a time,
    // so with four foundations every fourth launch is a new rank starting.
    expect(CascadePlayer.layerOf(~launched=0, ~seats=4))->toBe(0)
    expect(CascadePlayer.layerOf(~launched=3, ~seats=4))->toBe(0)
    expect(CascadePlayer.layerOf(~launched=4, ~seats=4))->toBe(1)
    // A stage with no seats has no rounds to count, which is what keeps a layer step from
    // paying anything on one.
    expect(CascadePlayer.layerOf(~launched=9, ~seats=0))->toBe(0)
  })

  test("waits for the seats to come round when that is the step it is on", () => {
    // Nothing is taken off while a rank is in the air, and the whole round's worth lands
    // as the next rank starts — so the brightest thing on the surface is the rank just
    // thrown rather than the stamp just laid.
    let player = ready(
      ~options={
        ...CascadePlayer.defaults,
        fade: {persistence: CascadePlayer.Cards(9.), step: CascadePlayer.Layer},
      },
    )
    let paidAt = []
    for stamp in 1 to 12 {
      let owed = player.fadeOwedMs
      CascadePlayer.dim(player, ~seats=4)
      if player.fadeOwedMs < owed {
        paidAt->Array.push(stamp)
      }

      // The run reaching its fourth and eighth card, which is where the seats come round.
      if stamp == 4 || stamp == 8 {
        player.run = {...player.run, launched: stamp}
      }
    }
    after(
      player,
      () => {
        expect(paidAt)->toEqual([5, 9])
        // …and with no card left to launch there is no round left to come, so the last
        // rank's trail stays where it is rather than sinking on a clock of its own. The
        // debt is still counted, so a step picked up mid-run pays what it owes.
        expect(player.fadeOwedMs)->toBe(3. *. CascadePlayer.defaults.stampMs)
      },
    )
  })

  test("spends every coin in full, so a run of stamps is worth what the seconds say", () => {
    // The debt is cleared by what was paid, not by a fixed amount, so nothing drifts
    // between one payment and the next.
    let player = ready()
    for _ in 1 to 10 {
      CascadePlayer.dim(player, ~seats=4)
    }
    after(player, () => expect(player.fadeOwedMs)->toBe(0.))
  })
})

describe("the cards out on their seats", () => {
  // A foundation shows one card at a time: the one about to be thrown. What is *out* is
  // what a caller has been told to show, and what the trail is kept off.
  let armed = (~launched, ~sinceLaunchMs, ~readyMs=250.) =>
    CascadePlayer.armedBy(~launched, ~cards=52, ~seats=4, ~sinceLaunchMs, ~launchMs=750., ~readyMs)

  test("starts with one on every seat, which is a board's opening pile tops", () => {
    expect(armed(~launched=0, ~sinceLaunchMs=0.))->toBe(4)
  })

  test("puts the next one out once its launch is within the notice it was given", () => {
    // Nothing new at half an interval; the next card at 500ms, which is 250 from going.
    expect(armed(~launched=4, ~sinceLaunchMs=375.))->toBe(4)
    expect(armed(~launched=4, ~sinceLaunchMs=500.))->toBe(5)
  })

  test("hands a caller no notice at all when it asked for none", () => {
    // A card out only as it goes: `armed` never runs ahead of `launched` past the seats.
    expect(armed(~launched=4, ~sinceLaunchMs=740., ~readyMs=0.))->toBe(4)
  })

  test("never runs past the deck it was given", () => {
    expect(armed(~launched=52, ~sinceLaunchMs=740.))->toBe(52)
  })

  let occupied = (~launched, ~armed) =>
    Array.make(~length=4, 0)->Array.mapWithIndex((_, seat) =>
      CascadePlayer.seatIsOccupied(~launched, ~armed, ~seats=4, ~seat)
    )

  test("sits them on the seats in the round-robin the cards leave in", () => {
    // `Cascade` launches card `i` from seat `i mod seats`, so the four out at the start
    // are one per seat, and each seat empties as its own card goes.
    expect(occupied(~launched=0, ~armed=4))->toEqual([true, true, true, true])
    expect(occupied(~launched=1, ~armed=4))->toEqual([false, true, true, true])
    expect(occupied(~launched=4, ~armed=4))->toEqual([false, false, false, false])
    // …and the next card out lands on the seat it belongs to, not on the next one along.
    expect(occupied(~launched=4, ~armed=5))->toEqual([true, false, false, false])
  })

  test("is nothing at all when there are no seats to speak of", () => {
    expect(CascadePlayer.seatIsOccupied(~launched=0, ~armed=4, ~seats=0, ~seat=0))->toBe(false)
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

  test("a fade is one of those: what you dim is the trail in front of you", () => {
    let player = ready()
    underway(player)
    CascadePlayer.retune(
      player,
      {...player.options, fade: {persistence: CascadePlayer.Seconds(2.), step: Coin(0.2)}},
    )
    after(
      player,
      () => {
        expect(player.run.launched)->toBe(1)
        expect(player.options.fade.persistence)->toEqual(CascadePlayer.Seconds(2.))
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
